#!/bin/sh
BASE=/home/geexbox/bot/buildbot
REPONAME=openbricks
REPOURL="https://github.com/OpenBricks/openbricks.git"
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
failed at '$1' stage,
----------

I was building from the $REPONAME repository at $REV revision on $DATE.
Attached, the log messages

buildbot
EOF

mpack -s "[buildbot] $NAME failed to build" -d /tmp/mesg.txt $BUILDLOG.bz2 tomlohave@gmail.com nicknickolaev@gmail.com r.ihle@s-t.de

}

create_img () {
  cd $1
  cd `ls .`
  if [ -f make-sdcard ] ; then
    a=`grep DEFAULT_TARGET= make-sdcard | cut -d= -f2 | cut -d\" -f2`
    b=`ls *.xz`
    c=`echo $b | sed -e 's/.tar.xz//'`.img
    sudo ./make-sdcard $c $b $a
  fi
}

clean_old_data () {
  # keep only 3 builds
    cd $1
    ls -dt ./* | tail -n +4 | xargs rm -rf || true
}

mkdir -p $BUILD $SOURCES $SNAPSHOTS $SNAPSHOTSD $STAMPS/$REPONAME $LOGS $BASE/src/.stamps
log "Starting"
if [ -r $STAMPS/lock ]; then
  log "Another buildbot instance (`cat $STAMPS/lock`) is running, aborting."
  exit 1
else
  /bin/echo -n $$ > $STAMPS/lock
  rm -Rf $BUILD/*
fi
if [ ! -d $REPO ]; then
  log "Cloning repo"
  git clone $REPOURL $REPO > /dev/null 2>&1
else
  log "Pulling repo"
  (cd $REPO; git pull -u > /dev/null 2>&1)
fi

cd $REPO
REV=`git log -1 --pretty="%h"`
cd ..

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
  git clone $REPO $NAME > $BUILDLOG
fi
rm -f "$BUILDLOG"
cd $NAME
#hg update -C >> $BUILDLOG 2>&1
git pull -u >> $BUILDLOG 2>&1
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

#find $SNAPSHOTS/openbricks/geexbox-xbmc-*/* -mtime +10 -delete
#find $SNAPSHOTS/data/openbricks/geexbox-xbmc-*/* -mtime +10 -delete
find $LOGS/$REPONAME/*.log* -mtime +10 -delete

# build configs
conf_enable="a10-cubieboard armada5xx-cubox bcm2708-raspberrypi bcm2709-raspberrypi2 i386-generic imx6-cuboxi imx6-utilite x86_64-generic"
for config_f in $conf_enable ; do
  if [ -L /tmp/openbricks ]  ; then
    rm /tmp/openbricks
  fi
  conffile="$REPO/config/defconfigs/geexbox-xbmc-$config_f.conf"
  cd $BUILD
  NAME=`basename $conffile .conf`
  mkdir -p $LOGS/$REPONAME
  BUILDLOG="$LOGS/$REPONAME/$NAME.$DATE.log"
  log "Building $NAME"
  if [ ! -d "$NAME" ]; then
    log "Cloning $NAME"
    rm -f $STAMPS/$NAME
    git clone $REPO $NAME > $BUILDLOG 
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
#  hg update -C >> $BUILDLOG 2>&1
  git pull -u >> $BUILDLOG 2>&1
  ./scripts/kconfiginit >> $BUILDLOG 2>&1
  if grep -q 'CONFIG_OPT_TARGET_FLAT=y' config/defconfigs/$NAME.conf; then
    sed \
      -e 's:CONFIG_OPT_TARGET_FLAT=y:# CONFIG_OPT_TARGET_FLAT is not set:' \
      -e 's:# CONFIG_OPT_TARGET_TARBALL is not set:CONFIG_OPT_TARGET_TARBALL=y:' \
      -e 's:CONFIG_OPT_CONCURRENCY_MAKE_LEVEL=8:CONFIG_OPT_CONCURRENCY_MAKE_LEVEL=8:' \
      -e 's:CONFIG_OPT_CONCURRENCY_MAKE_LEVEL=9:CONFIG_OPT_CONCURRENCY_MAKE_LEVEL=8:'\
      < config/defconfigs/$NAME.conf \
      > `ls -d build/build.host/kconfig-frontends-*`/.config
  else
    cp -P config/defconfigs/$NAME.conf `ls -d build/build.host/kconfig-frontends-*`/.config
  fi
  make silentoldconfig >> $BUILDLOG 2>&1 || true
  make quickclean >> $BUILDLOG 2>&1
  if [ $? -ne 0 ]; then
    log "$NAME quickclean failed"
    mailfail clean
    rm -f "$STAMPS/$REPONAME/$NAME"
    continue
  fi
  rm -rf binaries
  log "Making $NAME"
  local_rev=`git log -1 --pretty="%h"`
  make >> $BUILDLOG 2>&1
  if [ $? -eq 0 ]; then
    echo "Build successful : local revision is $local_rev" >> $BUILDLOG 2>&1
    log "$NAME build successful"
    echo $DATE > "$STAMPS/$REPONAME/$NAME"
    mkdir -p "$SNAPSHOTSD/$REPONAME/$NAME/$DATE"
    mkdir -p "$SNAPSHOTS/$REPONAME/$NAME"
    cp -PR binaries/* "$SNAPSHOTSD/$REPONAME/$NAME/$DATE"
    here=`pwd`
    create_img $SNAPSHOTSD/$REPONAME/$NAME/$DATE
    cd $here
    clean_old_data $SNAPSHOTSD/$REPONAME/$NAME
    cd $here
    rm -f $SNAPSHOTS/$REPONAME/$NAME/latest
    clean_old_data $SNAPSHOTS/$REPONAME/$NAME
    cd $here
    ln -sf $DATE "$SNAPSHOTS/$REPONAME/$NAME/latest"
    ln -sf ../../data/$REPONAME/$NAME/$DATE $SNAPSHOTS/$REPONAME/$NAME/$DATE
# delete all *-dbg_* packages
    find $SNAPSHOTS/data/openbricks/geexbox-xbmc-*/* -name *-dbg_* -delete
    make quickclean
    log "Archiving $NAME log"
    lbzip2 -9 $BUILDLOG
  else
    log "Archiving $NAME log"
    echo "Build failed : local revision is $local_rev" >> $BUILDLOG 2>&1
    lbzip2 -9 $BUILDLOG
    log "$NAME build failed"
    mailfail build
    rm -f "$STAMPS/$REPONAME/$NAME"
  fi
done

rm -f $STAMPS/lock
log "Quitting"
cp $LOGFILE $LOGS/$REPONAME/$REPONAME.$DATE.log
echo "" > $LOGFILE
lbzip2 -9 $LOGS/$REPONAME/$REPONAME.$DATE.log

