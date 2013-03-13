#!/bin/sh
BASE=/srv/buildbot
REPONAME=openbricks
REPOURL="http://hg.openbricks.org/openbricks"
REPO=$BASE/src/$REPONAME
SOURCES=$BASE/src/sources
BUILD=$BASE/build
SNAPSHOTS=$BASE/snapshots
SNAPSHOTSD=$BASE/snapshots/data
STAMPS=$BASE/stamps
LOGS=$BASE/logs
LOGFILE=$BASE/logs/$REPONAME.log
STAMPSGET=$BASE/src/.stamps

if [ -r $STAMPS/$REPONAME/rev ]; then
  OLDREV=`cat $STAMPS/$REPONAME/rev`
fi
DATE=`date +%Y%m%d`

log()
{
  NOW=`date "+%b %d %T"`
  echo "$NOW [$$] $1" >> $LOGFILE
}

mailfail()
{

cat > /tmp/mesg.txt <<EOF
Hi,

I was trying to build '$NAME', but something went wrong. The build
failed at '$1' stage, here's the last log messages:
----------
`tail -75 $BUILDLOG`
----------

I was building from the $REPONAME repository at $REV revision on $DATE.
You can find the full log attached.

buildbot
EOF

mpack -s "[buildbot] $NAME failed to build" -d /tmp/mesg.txt $BUILDLOG.bz2 devel@openbricks.org
}

sendsnapshot ()
{
  log "Rsyncing snapshots to fry (data)"
  rsync --bwlimit=75 --archive --delete $SNAPSHOTSD buildbot@fry.geexbox.org:/data/snapshots >> $BUILDLOG 2>&1
  if [ $? -eq 0 ]; then
    log "rsync successful, updating link now"
    rsync --bwlimit=75 --archive --delete $SNAPSHOTS/* buildbot@fry.geexbox.org:/data/snapshots >> $BUILDLOG 2>&1
    if [ $? -eq 0 ]; then
      log "rsync successful (links)"
    else
      log "rsync failed (links)"
    fi
  else
    log "rsync failed (data)"
  fi
}

mkdir -p $BUILD $SOURCES $SNAPSHOTS $SNAPSHOTSD $STAMPS/$REPONAME $LOGS $STAMPSGET
log "Starting"
if [ -r $STAMPS/lock ]; then
  log "Another buildbot instance (`cat $STAMPS/lock`) is running, aborting."
  exit 1
else
  /bin/echo -n $$ > $STAMPS/lock
fi
if [ ! -d $REPO ]; then
  log "Cloning repo"
  hg clone $REPOURL $REPO > /dev/null 2>&1
else
  log "Pulling repo"
  (cd $REPO; hg pull -u > /dev/null 2>&1)
fi
REV=`hg identify $REPO`
if [ "$REV" = "$OLDREV" ]; then
  log "Nothing new"
else
  log "Found new rev $REV, rebuilding everything"
  rm -f $STAMPS/$REPONAME/*
  echo $REV > $STAMPS/$REPONAME/rev
fi

# build docs
cd $BUILD
NAME=docs
mkdir -p $LOGS/$REPONAME
BUILDLOG="$LOGS/$REPONAME/$NAME.$DATE.log"
log "Building $NAME"
if [ ! -d "$NAME" ]; then
  log "Cloning $NAME"
  rm -f $STAMPS/$NAME
  hg clone $REPO $NAME > $BUILDLOG
fi
rm -f "$BUILDLOG"
cd $NAME
hg update -C >> $BUILDLOG 2>&1
hg pull -u >> $BUILDLOG 2>&1
cd DOCS
make clean >> $BUILDLOG 2>&1
if [ $? -ne 0 ]; then
  log "$NAME clean failed"
else
  make >> $BUILDLOG 2>&1
  if [ $? -eq 0 ]; then
    log "$NAME build successful"
    mkdir -p "$SNAPSHOTS/$REPONAME/$NAME/$DATE"
    cp -PR *.html *.pdf images "$SNAPSHOTS/$REPONAME/$NAME/$DATE/"
    cp -P $BASE/src/docs/*.png "$SNAPSHOTS/$REPONAME/$NAME/$DATE/images/"
    rm -f $SNAPSHOTS/$REPONAME/$NAME/latest
    ln -sf $DATE "$SNAPSHOTS/$REPONAME/$NAME/latest"
  else
    log "$NAME build failed"
  fi
fi

# Delete old snapshots
find $SNAPSHOTS/$REPONAME/geexbox-xbmc-*/* -mtime +60 -delete
find $SNAPSHOTSD/$REPONAME/geexbox-xbmc-*/* -mtime +60 -delete

# in case previous one failed and synchronize if we have deleted old snapshots
sendsnapshot

# build configs
for conffile in $REPO/config/defconfigs/*.conf; do
  cd $BUILD
  NAME=`basename $conffile .conf`
  mkdir -p $LOGS/$REPONAME
  BUILDLOG="$LOGS/$REPONAME/$NAME.$DATE.log"
  log "Building $NAME"
  if [ ! -d "$NAME" ]; then
    log "Cloning $NAME"
    rm -f $STAMPS/$NAME
    hg clone $REPO $NAME > $BUILDLOG 
    ln -s $SOURCES $NAME/sources
    ln -s $STAMPSGET $NAME/.stamps
  fi
  if [ "$STAMPS/$REPONAME/$NAME" -nt $conffile ]; then
    log "Build $NAME is up to date"
    continue
  fi
  rm -f "$BUILDLOG"
  rm -f "$STAMPS/$REPONAME/$NAME"
  cd $NAME
  hg update -C >> $BUILDLOG 2>&1
  hg pull -u >> $BUILDLOG 2>&1
  ./scripts/kconfiginit >> $BUILDLOG 2>&1
  if grep -q 'CONFIG_OPT_TARGET_FLAT=y' config/defconfigs/$NAME.conf; then
    sed \
      -e 's:CONFIG_OPT_TARGET_FLAT=y:# CONFIG_OPT_TARGET_FLAT is not set:' \
      -e 's:# CONFIG_OPT_TARGET_TARBALL is not set:CONFIG_OPT_TARGET_TARBALL=y:' \
      < config/defconfigs/$NAME.conf \
      > `ls -d build/build.host/kconfig-frontends-*`/.config
  else
    cp -P config/defconfigs/$NAME.conf `ls -d build/build.host/kconfig-frontends-*`/.config
  fi
  make silentoldconfig >> $BUILDLOG 2>&1 || true
#  if [ $? -ne 0 ]; then
#    log "$NAME config failed"
#    rm -f "$STAMPS/$REPONAME/$NAME"
#    continue
#  fi
  make quickclean >> $BUILDLOG 2>&1
  if [ $? -ne 0 ]; then
    log "$NAME quickclean failed"
    mailfail clean
    rm -f "$STAMPS/$REPONAME/$NAME"
    continue
  fi
  rm -rf binaries
  log "Making $NAME"
  make >> $BUILDLOG 2>&1
  if [ $? -eq 0 ]; then
    log "$NAME build successful"
    echo $DATE > "$STAMPS/$REPONAME/$NAME"
    mkdir -p "$SNAPSHOTSD/$REPONAME/$NAME/$DATE"
    mkdir -p "$SNAPSHOTS/$REPONAME/$NAME"
    cp -PR binaries/* "$SNAPSHOTSD/$REPONAME/$NAME/$DATE"
    rm -f $SNAPSHOTS/$REPONAME/$NAME/latest
    ln -sf $DATE "$SNAPSHOTS/$REPONAME/$NAME/latest"
    ln -sf ../../data/$REPONAME/$NAME/$DATE $SNAPSHOTS/$REPONAME/$NAME/$DATE
    sendsnapshot
    # send snapshot, don't wait
    make quickclean
    log "Archiving $NAME log"
    lbzip2 -9 $BUILDLOG
  else
    log "Archiving $NAME log"
    lbzip2 -9 $BUILDLOG
    log "$NAME build failed"
    mailfail build
    rm -f "$STAMPS/$REPONAME/$NAME"
  fi
done

rm -f $STAMPS/lock
log "Quitting"
