#!/bin/sh
REPONAME=openbricks
REPOURL="https://github.com/OpenBricks/openbricks.git"
REPOOWNERS="tomlohave@gmail.com nicknickolaev@gmail.com r.ihle@s-t.de"

ACTIVE_CONFIGS=" \
  geexbox-xbmc-a10-cubieboard \
  geexbox-xbmc-armada5xx-cubox \
  geexbox-xbmc-bcm2708-raspberrypi \
  geexbox-xbmc-bcm2709-raspberrypi2 \
  geexbox-xbmc-i386-generic \
  geexbox-xbmc-imx6-cuboxi \
  geexbox-xbmc-imx6-utilite \
  geexbox-xbmc-x86_64-generic \
"

BASE=$HOME/bot/buildbot
REPO=$BASE/src/$REPONAME
SOURCES=$BASE/src/sources
BUILD=$BASE/build
SNAPSHOTS=$BASE/snapshots
SNAPSHOTSD=$BASE/snapshots/data
STAMPS=$BASE/stamps
LOGS=$BASE/logs
LOGFILE=$BASE/logs/$REPONAME.log
STAMPSGET=$BASE/src/.stamps

DATE=`date +%Y%m%d`

log() {
  NOW=`date "+%b %d %T"`
  echo "$NOW [$$] $1" >> $LOGFILE
}

compress() {
  #lbzip2 -9 $1
  xz -zfe $1
}

mailfail() {
cat > /tmp/mesg.txt <<EOF
Hi,

I was trying to build '$CONFNAME', but something went wrong. The build
failed at '$1' stage,
----------

I was building from the $REPONAME repository at $REV revision on $DATE.
Attached, the log messages

buildbot
EOF

  mpack -s "[buildbot] $CONFNAME failed to build" -d /tmp/mesg.txt $BUILDLOG.?z* $REPOOWNERS
}

create_img () {
  cd $1/*
  if [ -f make-sdcard ]; then
    a=`grep DEFAULT_TARGET= make-sdcard | cut -d= -f2 | cut -d\" -f2`
    b=`ls *.xz`
    c=`echo $b | sed -e 's/.tar.xz//'`.img
    sudo ./make-sdcard $c $b $a
  fi
  cd -
}

clean_old_data () {
  # keep only 3 builds
  ls -dt $1/* | tail -n +4 | xargs rm -rf || true
}

prepare_to_build() {
  CONFNAME=$1
  CONFFILE=$2

  # remove symlink
  [ -L /tmp/openbricks ] && rm /tmp/openbricks

  mkdir -p $LOGS/$REPONAME
  BUILDLOG="$LOGS/$REPONAME/$CONFNAME.$DATE.log"

  log "Building $CONFNAME"
  if [ ! -d "$CONFNAME" ]; then
    log "Cloning $CONFNAME"
    rm -f $STAMPS/$CONFNAME
    git clone $REPO $CONFNAME > $BUILDLOG
    
    # set links to source packages and download timestamps
    if [ -n "$CONFFILE" ]; then
      ln -s $SOURCES $CONFNAME/sources
      ln -s $STAMPSGET $CONFNAME/.stamps
    fi
  fi
  
  if [ -z "$CONFFILE" ] || \
     [ ! -e "$STAMPS/$REPONAME/$CONFNAME" ] || \
     [ "$CONFFILE" -nt "$STAMPS/$REPONAME/$CONFNAME" ]; then  
    rm -f "$BUILDLOG"
    rm -f "$STAMPS/$REPONAME/$CONFNAME"

    (cd $CONFNAME; git pull -u >> $BUILDLOG 2>&1)
    touch $CONFNAME/NEED_REBUILD
  else
    log "Build $CONFNAME is up to date"
    rm -f $CONFNAME/NEED_REBUILD
  fi
}


# Create directories
log "Starting"
mkdir -p $BUILD $SOURCES $SNAPSHOTS $SNAPSHOTSD $STAMPS/$REPONAME $LOGS $BASE/src/.stamps

# Check for re-entry
if [ -r $STAMPS/lock ]; then
  log "Another buildbot instance (`cat $STAMPS/lock`) is running, aborting."
  exit 1
fi

/bin/echo -n $$ > $STAMPS/lock
rm -rf $BUILD/*

# delete old logs
find $LOGS/$REPONAME/*.log* -mtime +10 -delete

# Refresh repo
if [ ! -d $REPO ]; then
  log "Cloning repo $REPONAME"
  git clone $REPOURL $REPO > /dev/null 2>&1
else
  log "Pulling repo $REPONAME"
  (cd $REPO; git pull -u > /dev/null 2>&1)
fi

# Check for revision change
cd $REPO
REV=`git log -1 --pretty="%h"`
cd ..

if [ -r $STAMPS/$REPONAME/rev ]; then
  OLDREV=`cat $STAMPS/$REPONAME/rev`
fi

if [ "$REV" = "$OLDREV" ]; then
  log "Nothing new"
else
  log "Found new rev $REV, rebuilding everything"
  rm -f $STAMPS/$REPONAME/*
  echo $REV > $STAMPS/$REPONAME/rev
fi


# build documentation
cd $BUILD
prepare_to_build docs ""

if [ -e $CONFNAME/NEED_REBUILD ]; then
  cd $CONFNAME/DOCS

  log "Cleaning $CONFNAME"
  make clean >> $BUILDLOG 2>&1
  if [ $? -ne 0 ]; then
    log "$CONFNAME clean failed"
  else
    log "Making $CONFNAME"
    make >> $BUILDLOG 2>&1
    if [ $? -ne 0 ]; then
      log "$CONFNAME build failed"
    else
      log "$CONFNAME build successful"
      mkdir -p "$SNAPSHOTS/$REPONAME/$CONFNAME/$DATE"
      cp -PR *.html *.pdf images "$SNAPSHOTS/$REPONAME/$CONFNAME/$DATE/"
      #cp -P $BASE/src/docs/*.png "$SNAPSHOTS/$REPONAME/$CONFNAME/$DATE/images/"

      rm -f "$SNAPSHOTS/$REPONAME/$CONFNAME/latest"            
      clean_old_data "$SNAPSHOTS/$REPONAME/$CONFNAME"

      ln -sf $DATE "$SNAPSHOTS/$REPONAME/$CONFNAME/latest"
    fi
  fi
fi


# build active configurations
for c in $ACTIVE_CONFIGS; do
  cd $BUILD
  prepare_to_build "$c" "$REPO/config/defconfigs/$c.conf"

  if [ -e $CONFNAME/NEED_REBUILD ]; then
    cd $CONFNAME
    
    log "Configuring $CONFNAME"
    ./scripts/kconfiginit >> $BUILDLOG 2>&1
    if grep -q 'CONFIG_OPT_TARGET_FLAT=y' $CONFFILE; then
      sed \
        -e 's:CONFIG_OPT_TARGET_FLAT=y:# CONFIG_OPT_TARGET_FLAT is not set:' \
        -e 's:# CONFIG_OPT_TARGET_TARBALL is not set:CONFIG_OPT_TARGET_TARBALL=y:' \
        -e 's:CONFIG_OPT_CONCURRENCY_MAKE_LEVEL=[0|9]:CONFIG_OPT_CONCURRENCY_MAKE_LEVEL=8:' \
        < $CONFFILE > `ls -d build/build.host/kconfig-frontends-*`/.config
    else
      cp -P $CONFFILE `ls -d build/build.host/kconfig-frontends-*`/.config
    fi
    
    make silentoldconfig >> $BUILDLOG 2>&1 || true

    log "Cleaning $CONFNAME"
    make quickclean >> $BUILDLOG 2>&1
    if [ $? -ne 0 ]; then
      log "$CONFNAME quickclean failed"
      mailfail clean
      rm -f "$STAMPS/$REPONAME/$CONFNAME"
      continue
    fi
    
    log "Making $CONFNAME"
    rm -rf binaries
    local_rev=`git log -1 --pretty="%h"`    

    make >> $BUILDLOG 2>&1
    if [ $? -ne 0 ]; then
      log "Archiving $CONFNAME log"
      echo "Build failed : local revision is $local_rev" >> $BUILDLOG 2>&1
      compress $BUILDLOG
      log "$CONFNAME build failed"
      mailfail build
      rm -f "$STAMPS/$REPONAME/$CONFNAME"
      continue
    fi

    echo "Build successful : local revision is $local_rev" >> $BUILDLOG 2>&1
    log "$CONFNAME build successful"
    echo $DATE > "$STAMPS/$REPONAME/$CONFNAME"
    mkdir -p "$SNAPSHOTSD/$REPONAME/$CONFNAME/$DATE"
    mkdir -p "$SNAPSHOTS/$REPONAME/$CONFNAME"
    cp -PR binaries/* "$SNAPSHOTSD/$REPONAME/$CONFNAME/$DATE"
    # delete debug packages
    find "$SNAPSHOTSD/$REPONAME/$CONFNAME/$DATE" -name *-dbg_*.opk -delete
    # create disk images
    create_img $SNAPSHOTSD/$REPONAME/$CONFNAME/$DATE

    # remove old snapshots
    clean_old_data $SNAPSHOTSD/$REPONAME/$CONFNAME

    # re-create links
    rm -f $SNAPSHOTS/$REPONAME/$CONFNAME/*    
    for d in $SNAPSHOTSD/$REPONAME/$CONFNAME; do
      n=`basename $d`
      ln -sf ../../data/$REPONAME/$CONFNAME/$n $SNAPSHOTS/$REPONAME/$CONFNAME/$n
    done
    ln -sf $DATE $SNAPSHOTS/$REPONAME/$CONFNAME/latest

    log "Archiving $CONFNAME log"
    compress $BUILDLOG
    
    make quickclean
  fi
done


# rotate log file
log "Quitting"
mv -f $LOGFILE $LOGS/$REPONAME/$REPONAME.$DATE.log
compress $LOGS/$REPONAME/$REPONAME.$DATE.log

rm -f $STAMPS/lock
exit 0
