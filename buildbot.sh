#!/bin/sh
BASE=/srv/buildbot
REPONAME=openbricks
REPOURL="http://hg.openbricks.org/openbricks"
REPO=$BASE/src/$REPONAME
SOURCES=$BASE/src/sources
BUILD=$BASE/build
SNAPSHOTS=$BASE/snapshots
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
  mail -s "[buildbot] $NAME failed to build" devel@openbricks.org <<EOF
Hi,

I was trying to build '$NAME', but something went wrong. The build
failed at '$1' stage, here's the last log messages:
----------
`tail -50 $BUILDLOG`
----------

I was building from the $REPONAME repository at $REV revision on $DATE.
You can find the full log at
buildbot:${BUILDLOG}
If you don't know how to access buildbot, email davide for an account.

buildbot
EOF
}

mkdir -p $BUILD $SOURCES $SNAPSHOTS $STAMPS/$REPONAME $LOGS $STAMPSGET
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
  make clean >> $BUILDLOG 2>&1
  if [ $? -ne 0 ]; then
    log "$NAME clean failed"
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
    mkdir -p "$SNAPSHOTS/$REPONAME/$NAME/$DATE"
    cp -PR binaries/* "$SNAPSHOTS/$REPONAME/$NAME/$DATE"
    rm -f $SNAPSHOTS/$REPONAME/$NAME/latest
    ln -sf $DATE "$SNAPSHOTS/$REPONAME/$NAME/latest"
  else
    log "$NAME build failed"
    mailfail build
    rm -f "$STAMPS/$REPONAME/$NAME"
  fi
  log "Archiving $NAME log"
  lbzip2 -9 $BUILDLOG
done

log "Rsyncing snapshots to fry"
rsync --archive --delete $SNAPSHOTS/* buildbot@fry.geexbox.org:/data/snapshots >> $BUILDLOG 2>&1
if [ $? -eq 0 ]; then
  log "rsync successful"
else
  log "rsync failed"
fi
rm -f $STAMPS/lock
log "Quitting"
