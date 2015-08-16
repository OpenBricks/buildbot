#!/bin/sh
REPONAME=openbricks
REPOBRANCH=master
REPOURL="https://github.com/OpenBricks/openbricks.git"
REPOOWNERS="tomlohave@gmail.com nicknickolaev@gmail.com r.ihle@s-t.de"

# specify the PID of the currently running build to exit gracefully
CANCEL_PID=""

ACTIVE_CONFIGS=" \
  geexbox-kodi-imx6-cuboxi \
  geexbox-kodi-imx6-utilite \
  geexbox-xbmc-a10-cubieboard \
  geexbox-xbmc-armada5xx-cubox \
  geexbox-xbmc-bcm2708-raspberrypi \
  geexbox-xbmc-bcm2709-raspberrypi2 \
  geexbox-xbmc-i386-generic \
  geexbox-xbmc-imx6-cuboxi \
  geexbox-xbmc-imx6-utilite \
  geexbox-xbmc-x86_64-generic \
  geexbox-kodi-bcm2708-raspberrypi \
  geexbox-kodi-bcm2709-raspberrypi2 \
  geexbox-kodi-i386-generic \
"

BASE=/home/geexbox/bot/buildbot

BUILD=$BASE/build
REPO=$BASE/src/$REPONAME
SOURCES=$BASE/src/sources
STAMPSGET=$BASE/src/.stamps
SNAPSHOTS=$BASE/snapshots
SNAPSHOTSD=$BASE/snapshots/data
LOGS=$BASE/logs
LOGFILE=$BASE/logs/$REPONAME.log
STAMPS=$BASE/stamps
PIDFILE=$STAMPS/lock
BRKFILE=$STAMPS/cancel

DATE=`date +%Y%m%d`

log() {
  NOW=`date "+%b %d %T"`
  echo "$NOW [$$] $1" >> $LOGFILE
}

compress() {
  [ -n "$2" ] && log "Archiving log $2"
  #lbzip2 -9f $1
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
  local name=`basename *.tar.xz .tar.xz`
  if [ -f make-sdcard ]; then
    sudo rm -f /tmp/$CONFNAME.img*
    sudo ./make-sdcard /tmp/$CONFNAME.img $name.tar.xz
    sudo chown --reference=$name.tar.xz /tmp/$CONFNAME.img*
    [ -f /tmp/$CONFNAME.img.xz ] && mv /tmp/$CONFNAME.img.xz ./$name.img.xz
    rm -f /tmp/$CONFNAME.img*
  fi
}

clean_old_data () {
  # keep only 3 builds
  ls -dt $1/* | tail -n +4 | xargs rm -rf || true
}

git_pull_branch () {
  rm -f .GIT_REVISION
  git fetch origin >> $2 2>&1
  git branch $1 -t origin/$1 > /dev/null 2>&1 || true
  if git branch -l | grep -qw $1; then
    git checkout $1 >> $2 2>&1
    git merge origin/$1 >> $2 2>&1
    git log -1 --pretty="%h" > .GIT_REVISION
    echo "Branch $1, revision `cat .GIT_REVISION`" >> $2
  else
    echo "Branch $1 does not exist" >> $2
  fi
}

prepare_to_build() {
  CONFNAME=$1
  CONFFILE=$2

  # remove symlink
  [ -L /tmp/openbricks ] && rm /tmp/openbricks

  BUILDLOG="$LOGS/$REPONAME/$CONFNAME.$DATE.log"
  rm -f "$BUILDLOG"

  # create sub-repo
  log "Building $CONFNAME"
  if [ ! -d "$CONFNAME" ]; then
    log "Cloning $CONFNAME"
    rm -f $STAMPS/$CONFNAME
    git clone $REPO $CONFNAME > $BUILDLOG

    # set links to source packages and download timestamps
    ln -s $SOURCES $CONFNAME/sources
    ln -s $STAMPSGET $CONFNAME/.stamps
  fi

  # refresh sub-repo
  rm -f $CONFNAME/.NEED_REBUILD
  if [ -z "$CONFFILE" ] || \
     [ ! -e "$STAMPS/$REPONAME/$CONFNAME" ] || \
     [ "$CONFFILE" -nt "$STAMPS/$REPONAME/$CONFNAME" ]; then
    rm -f "$STAMPS/$REPONAME/$CONFNAME"

    log "Pulling $CONFNAME/$REPOBRANCH"
    (cd $CONFNAME; git_pull_branch $REPOBRANCH $BUILDLOG)
    if [ -r $CONFNAME/.GIT_REVISION ]; then
      touch $CONFNAME/.NEED_REBUILD
    else
      log "Branch $REPOBRANCH does not exist, skipping"
    fi
  else
    rm -f "$BUILDLOG"
    log "Build $CONFNAME is up to date"
  fi
}


# Create directories
mkdir -p $BUILD $SOURCES $STAMPSGET $SNAPSHOTS/$REPONAME $SNAPSHOTSD/$REPONAME $STAMPS/$REPONAME $LOGS/$REPONAME
log "Starting buildbot"

# Check for re-entry
if [ -r $PIDFILE ]; then
  other=`cat $PIDFILE`
  log "Another buildbot instance ($other) is running, aborting."

  if [ -n "$CANCEL_PID" ] && [ "$CANCEL_PID" = "$other" ]; then
    log "Issuing cancel request for instance $other"
    cp $PIDFILE $BRKFILE
  fi

  exit 1
fi

/bin/echo -n $$ > $PIDFILE

# delete old builds (!!! forces a full rebuild each time !!!)
rm -rf $BUILD/*

# delete inactive snapshots
for d in $SNAPSHOTSD/$REPONAME/*; do
  if [ -d $d ]; then
    n=`basename $d`
    if echo "$ACTIVE_CONFIGS" | grep -qvw $n; then
      log "Removing inactive platform $n"
      rm -rf $d $SNAPSHOTS/$REPONAME/$n $LOGS/$REPONAME/$n.*
    fi
  fi
done

# delete old logs
find $LOGS/$REPONAME -name "*.log*" -mtime +7 -delete


# Create repo
if [ ! -d $REPO ]; then
  log "Cloning repo $REPONAME"
  git clone $REPOURL $REPO > /dev/null 2>&1
fi

# Refresh repo
log "Pulling $REPONAME/$REPOBRANCH"
(cd $REPO; git_pull_branch $REPOBRANCH /dev/null)
if [ ! -r $REPO/.GIT_REVISION ]; then
  log "Branch $REPOBRANCH does not exist, aborting."
  rm -f $PIDFILE
  exit 1
fi

REV=`cat $REPO/.GIT_REVISION`

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
prepare_to_build docs "$STAMPS/$REPONAME/rev"

if [ -e $CONFNAME/.NEED_REBUILD ]; then
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
      mkdir -p $SNAPSHOTS/$REPONAME/$CONFNAME/$DATE
      cp -PR *.html *.pdf images $SNAPSHOTS/$REPONAME/$CONFNAME/$DATE/
      #cp -P $BASE/src/docs/*.png $SNAPSHOTS/$REPONAME/$CONFNAME/$DATE/images/

      rm -f $SNAPSHOTS/$REPONAME/$CONFNAME/latest
      clean_old_data $SNAPSHOTS/$REPONAME/$CONFNAME

      ln -sf $DATE $SNAPSHOTS/$REPONAME/$CONFNAME/latest

      echo $DATE > $STAMPS/$REPONAME/$CONFNAME
    fi
  fi

  compress $BUILDLOG $CONFNAME
fi


# build active configurations
for c in $ACTIVE_CONFIGS; do
  cd $BUILD
  prepare_to_build "$c" "$REPO/config/defconfigs/$c.conf"

  if [ -e $CONFNAME/.NEED_REBUILD ]; then
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
      compress $BUILDLOG $CONFNAME
      mailfail clean
      rm -f $STAMPS/$REPONAME/$CONFNAME

      continue
    fi

    log "Making $CONFNAME"
    rm -rf binaries
    local_rev=`git log -1 --pretty="%h"`

    make >> $BUILDLOG 2>&1
    if [ $? -ne 0 ]; then
      echo "Build failed : local revision is $local_rev" >> $BUILDLOG
      log "$CONFNAME build failed"
      compress $BUILDLOG $CONFNAME
      mailfail build
      rm -f $STAMPS/$REPONAME/$CONFNAME

      make quickclean > /dev/null 2>&1
      continue
    fi

    echo "Build successful : local revision is $local_rev" >> $BUILDLOG
    log "$CONFNAME build successful"
    echo $DATE > $STAMPS/$REPONAME/$CONFNAME

    # create data directory
    mkdir -p $SNAPSHOTSD/$REPONAME/$CONFNAME/$DATE
    rm -rf $SNAPSHOTSD/$REPONAME/$CONFNAME/$DATE/*

    # delete debug packages
    find binaries/binaries.* -name "*-dbg_*.opk" -delete

    # move binaries
    mv binaries/binaries.* $SNAPSHOTSD/$REPONAME/$CONFNAME/$DATE
    if [ $? -ne 0 ]; then
      log "$CONFNAME move failed"
      mailfail move
      rm -f $STAMPS/$REPONAME/$CONFNAME
    fi

    # create disk images
    (cd $SNAPSHOTSD/$REPONAME/$CONFNAME/$DATE/binaries.*; create_img)
    # remove old snapshots
    clean_old_data $SNAPSHOTSD/$REPONAME/$CONFNAME

    # create link directory
    mkdir -p $SNAPSHOTS/$REPONAME/$CONFNAME
    # re-create links
    rm -f $SNAPSHOTS/$REPONAME/$CONFNAME/*
    for d in $SNAPSHOTSD/$REPONAME/$CONFNAME/*; do
      n=`basename $d`
      ln -sf ../../data/$REPONAME/$CONFNAME/$n $SNAPSHOTS/$REPONAME/$CONFNAME/$n
    done
    ln -sf $DATE $SNAPSHOTS/$REPONAME/$CONFNAME/latest

    #make quickclean > /dev/null 2>&1
    rm -rf build/*

    compress $BUILDLOG $CONFNAME
  fi

  # check for cancel request
  if [ -r $BRKFILE ] && [ "$$" = "`cat $BRKFILE`" ]; then
    log "Cancelled after making $CONFNAME"
    rm -f $BRKFILE
    break
  fi
done


# rotate log file
log "Quitting"
touch $LOGFILE
mv -f $LOGFILE $LOGS/$REPONAME/$REPONAME.$DATE.log
compress $LOGS/$REPONAME/$REPONAME.$DATE.log

rm -f $PIDFILE
exit 0
