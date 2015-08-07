#! /bin/sh

BOTROOT=$HOME/newbot

if [ -d $BOTROOT ]; then
  echo "Already deployed"
  exit 1
fi

BOTROOT_TEMP=$HOME/newbot.ins
mkdir -p $BOTROOT_TEMP

BRANCH=newbot
ARCHIVE=$BOTROOT_TEMP/$BRANCH.tar.gz
wget "https://github.com/OpenBricks/buildbot/archive/$BRANCH.tar.gz" -O $ARCHIVE
if ! tar -C $BOTROOT_TEMP -xf $ARCHIVE --strip-components=1; then
  echo "Integrity check failed for $ARCHIVE"
  exit 2
fi

if [ ! -e $BOTROOT_TEMP/buildbot.conf ] || \
   [ ! -x $BOTROOT_TEMP/buildbot-update ]; then
  echo "Update script missing"
  exit 3
fi

rm -f $ARCHIVE

mv $BOTROOT_TEMP $BOTROOT
if [ ! -d $BOTROOT ]; then
  echo "Directory missing"
  exit 4
fi

TEMPFILE=$BOTROOT/crontab.tmp
crontab -l | grep -v "/buildbot-" | grep -v "^$" > $TEMPFILE

cat >> $TEMPFILE <<EOF

@reboot		$BOTROOT/buildbot-init
*/5 * * * *	$BOTROOT/buildbot-ping
2 * * * *	$BOTROOT/buildbot-update
7 * * * *	$BOTROOT/buildbot-run
11 * * * *	$BOTROOT/buildbot-sync
EOF

crontab $TEMPFILE
rm -f $TEMPFILE

crontab -l > $TEMPFILE
if grep -q "$BOTROOT/buildbot-.*" $TEMPFILE; then
  rm -f $TEMPFILE
  echo "Successfully deployed $BRANCH"
  exit 0
fi

echo "Crontab not updated"
rm -rf $BOTROOT
exit 5
