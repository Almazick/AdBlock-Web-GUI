#!/bin/sh
# AdBlock Web GUI by Almaz
# Version: 1.51
# Using Tomato firmware just put all the files in /var/wwwext/
# You can access GUI by openning in browser http://routerIP/ext/ads.sh
###############################################################################
adblockpath="/var/wwwext/adblock.sh"    # location of adblock.sh by Jerrm
pixelservip="192.168.1.254"             # Pixelserv IP address    
scriptname="ads.sh"                     # this script name
dnsmasqlog="/tmp/var/log/messages*"     # dnsmasq log location, by default it's using syslog
tmpfolder="/tmp"                        # location of your temp folder
dnsmasq_external_log="n"                # for external dnsmasq log then enter "y" otherwise "n" for default syslog
dnsmasqconf="/etc/dnsmasq.custom"       # location for dnsmasq.custom
###############################################################################
if ! grep -q 'adscount' $adblockpath
then
sed '/elog "$(wc -l < "$blocklist") unique hosts to block"/ a \echo $(wc -l < "$blocklist") > dummyname5/adscount' $adblockpath > $tmpfolder/tmp090; mv $tmpfolder/tmp090 $adblockpath
sed -i "s|dummyname5|"$tmpfolder"|g" $adblockpath
chmod +x $adblockpath
fi

REFRESHTIME=60
NEXTACTION=""
case $QUERY_STRING in
  force)
  REFRESHTIME=5;
  NEXTACTION="?doforce";
  ;;
  dnsmasqtoggle)
  REFRESHTIME=5;
  NEXTACTION="?dodnsmasqtoggle";
  ;;
  start)
  REFRESHTIME=5;
  NEXTACTION="?dostart";
  ;;
  restart)
  REFRESHTIME=5;
  NEXTACTION="?dorestart";
  ;;
  stop)
  REFRESHTIME=5;
  NEXTACTION="?dostop";
  ;;
  *)
  REFRESHTIME=60;
  NEXTACTION="";
  ;;
esac

cat << EOF
<!DOCTYPE html>
<html>
<head>
<title>adblock status</title>
<meta http-equiv="refresh" content="$REFRESHTIME; URL=$scriptname$NEXTACTION">
<style type="text/css">
body {
  margin: 0;
  padding: 1px 1px 1px 1px;
  height: 100%;
  overflow-y: auto;
}
#status {
  display: block;
  top: 0px;
  left: 0px;
  padding: 1px 1px 1px 1px;
  width: 150px;
  height: 115px;
  position: fixed;
  background-color: #ffffff;
  border: 1px solid #888;
}
#actions {
  display: block;
  top: 0px;
  left: 150px;
  padding: 1px 1px 1px 1px;
  width: 150px;
  height: 115px;
  position: fixed;
  background-color: #ffffff;
  border: 1px solid #888;
}
#time {
  display: block;
  top: 0px;
  left: 300px;
  padding: 1px 1px 1px 1px;
  width: 100%;
  height: 115px;
  position: fixed;
  background-color: #ffffff;
  border: 1px solid #888;
}
#blocks {
  float:left;
  width:50%;    
  overflow:auto;
  margin:auto;
  margin-top: 120px;
  display: block;
}
#blocks2 {
  float: right;
  width:50%; 
  overflow:auto;
  margin-top: 120px;
  display: block;
}
</style>
</head>
<body>
<script>
  var count=$REFRESHTIME;
  var counter=setInterval(timer, 1000);
  function timer()
  {
  count=count-1;
  document.getElementById("timer").innerHTML=count;
  if (count <= 0)
  {
  clearInterval(counter);
  return;
  }
  }
</script>
EOF
  echo '<div id="blocks2">'
  echo 'Not blocked last domain names:<br><pre>'
  egrep -B1 "reply .* is .*" /tmp/var/log/messages* | grep -v 'forwarded' | grep -v 'NODATA-IPv6' | sort -r | sed '/ reply /!d;s//&\n/;s/.*\n//;:a;/ is /bb;$!{n;ba};:b;s//\n&/;P;D' | awk '!a[$0]++' | tail -n 200
  echo '<p></div>'
echo '<div id="status">'
echo '<b>adblock status:</b><br>'
case $QUERY_STRING in
  force)
  echo 'starting/updating adblock...<p></div>'

  echo '<div id="actions">'
  echo '<b>adblock actions:</b>'
  echo '<br><i>please wait...</i>'
  echo '<p></div>'
  ;;
  dodnsmasqtoggle)
  echo 'DNSMASQ LOG<p></div>'

  echo '<div id="actions">'
  echo '<b>adblock actions:</b>'
  echo '<br><i>please wait...</i>'
  echo '<p></div>'

  echo '<div id="blocks"><pre>'
    if grep -Fxq 'log-queries' $dnsmasqconf
	then
	touch $tmpfolder/dnsmasqtmp
	sed 's/\<log-queries\>//g' $dnsmasqconf > "$tmpfolder/dnsmasqtmp"
	mv $tmpfolder/dnsmasqtmp $dnsmasqconf
	echo ""
	echo "DNSMASQ LOG DISABLED"
	else
	echo 'log-queries' >> $dnsmasqconf
	echo ""
	echo "DNSMASQ LOG ENABLED"
	fi
  service dnsmasq restart
  echo '</pre><p></div>'
  ;;
  doforce)
  echo 'force complete<p></div>'

  echo '<div id="actions">'
  echo '<b>adblock actions:</b>'
  echo '<br><i>please wait...</i>'
  echo '<p></div>'

  echo '<div id="blocks"><pre>'
  $adblockpath force
  echo '</pre><p></div>'
  ;;
  start)
  echo 'starting/updating adblock...<p></div>'

  echo '<div id="actions">'
  echo '<b>adblock actions:</b>'
  echo '<br><i>please wait...</i>'
  echo '<p></div>'
  ;;
  dostart)
  echo 'start/update complete<p></div>'

  echo '<div id="actions">'
  echo '<b>adblock actions:</b>'
  echo '<br><i>please wait...</i>'
  echo '<p></div>'

  echo '<div id="blocks"><pre>'
  $adblockpath
  echo '</pre><p></div>'
  ;;
  restart)
  echo 'restarting adblock...<p></div>'

  echo '<div id="actions">'
  echo '<b>adblock actions:</b>'
  echo '<br><i>please wait...</i>'
  echo '<p></div>'
  ;;
  dorestart)
  echo 'restart complete<p><pre></div>'

  echo '<div id="actions">'
  echo '<b>adblock actions:</b>'
  echo '<br><i>please wait...</i>'
  echo '<p></div>'

  echo '<div id="blocks"><pre>'
  $adblockpath restart
  echo '</pre><p></div>'
  ;;
  stop)
  echo 'stopping adblock...<p></div>'

  echo '<div id="actions">'
  echo '<b>adblock actions:</b>'
  echo '<br><i>please wait...</i>'
  echo '<p></div>'
  ;;
  dostop)
  echo 'stop completed<p><pre></div>'

  echo '<div id="actions">'
  echo '<b>adblock actions:</b>'
  echo '<br><i>please wait...</i>'
  echo '<p></div>'

  echo '<div id="blocks"><pre>'
  $adblockpath stop
  echo '</pre><p></div>'
  ;;
  *)
  echo 'blocklist '
  if nslookup ad-clix.com | grep -q $pixelservip ; then
  echo up
  else
  echo down
  fi
  echo '<br>iptables '
  echo `iptables -L | grep -c $pixelservip`

  echo '<br>pixelserv '
  if ps | grep -q pixelserv ; then
  echo up
  else
  echo down
  fi
 
  echo '<br>hosts'
  if [ -f $tmpfolder/adscount ];
  then
  cat $tmpfolder/adscount
  else
  echo "!!!Restart!!!"
  fi
  
  echo '<p></div>'

  echo '<div id="actions">'
  echo '<b>adblock actions:</b>'
  echo '<br><a href='$scriptname?force'>force</a>'
  echo '<br><a href='$scriptname?start'>start/update</a>'
  echo '<br><a href='$scriptname?restart'>restart</a>'
  echo '<br><a href='$scriptname?stop'>stop</a>'
  echo '<p></div>'

  echo '<div id="blocks">'
  echo 'Last blocked domain names:<br><pre>'
  if [ $dnsmasq_external_log = "n" ]
	then
		egrep -B1 "config .* is $pixelservip" $dnsmasqlog | egrep 'query.* from ' | grep -v 'from 127.0.0.1' | tail -n 100 | sed 's|^\(.*:..:..\) .*: quer|\1 |' | awk '{printf("%s %s %s) %-13s %s\n", $1,$2,$3,$7,$5)}' | sed -r 's:^/tmp/var/log/messages(.0)*-::' | sed 's/[)]//' | sort -r
	else
		grep -B1 $pixelservip $dnsmasqlog | egrep 'query.* from ' | grep -v 'from 127.0.0.1' | awk '{printf("%s %s %s %-13s %s\n", $1,$2,$3,$8,$6)}' | tail -n 100 | sort -r 
  fi
  echo '</pre><p></div>'
  ;;
esac

echo '<div id="time">'
echo '<b>time info:</b><br>'
echo `uptime`

cat << EOF
<br>page will automatically refresh in <span id="timer">$REFRESHTIME</span> seconds
<br>...or click <a href='$scriptname'>here</a> to refresh manually
EOF
if [ -f $dnsmasqconf ];
then
if grep -Fxq 'log-queries' $dnsmasqconf
then
echo '<br>dnsmasq log enabled click to <a href='$scriptname?dnsmasqtoggle'>DISABLE</a>'
else
echo '<br>dnsmasq log disabled click to <a href='$scriptname?dnsmasqtoggle'>ENABLE</a>'
fi
fi
cat << EOF
</div>
</body>
</html>
EOF