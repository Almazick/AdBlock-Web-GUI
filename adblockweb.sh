#!/bin/sh

# Adapted from adblock web script originated by HunterZ, with additions from AndreDVJ, Almaz and probably others
# http://www.linksysinfo.org/index.php?threads/script-clean-lean-and-mean-adblocking.68464/page-7#post-248495
#
# This version must be called via adblock.sh, and assumes it will inherit many
# settings from adblock.  The result should be a simple drop-in script without
# needing any modifications.

# values inherited from adblock
# =============================
# $adblockscript	main adblock script
# $binprefix		path to main adblock script
# $blacklist		blacklist file
# $blocklist		blocklist file
# $chain		iptables chain used for firewall rules
# $config		adblock config file
# $dnsmasq_config	dnsmasq.conf file
# $hostlink		HOST mode hosts file
# $listprefix		path to transient files - blocklist, source files, etc. Should be the same as prefix unless RAMLIST=1
# $modehost		use to test adblock mode - nslookup $LISTMODE.$modehost
# $pixelbin		pixelserv executable
# $prefix		path to permanent adblock files -  whitelist, blacklist
# $redirip		ip used for pixelserv
# $testhost		use to test if adblock is loaded - nslookup $testhost
# $weblink		symlink for web interface
# $webscript		script for web interface  (this script)
# $whitelist		whitelist file
# $PIXEL_IP		last octect of generated pixelserv ip - "0" meaand pixelserv disabled in adblock.
# $LISTMODE		adblock listmode - LEGACY/OPTIMIZE/HOST
#
# $web*			any variables added to adblock config beginning with "web" will also be exported
#

############################################################################
scriptname="${weblink##*"/"}" 		# This script's name
dnsmasqlog="$(nvram get log_file_path)"	# dnsmasq log location, default to syslog
dnsmasq_external_log="n"		# default to no external log
myenv=$(set)
############################################################################

readconf() {
loopcheck="$loopcheck ""$1"
for c in $(head -n 100 $1 | sed 's/#.*$//g' | sed -e 's/^[ \t]*//' | egrep "log-queries|log-facility=|conf-file=|local-ttl=")
do
  r="${c#*=}"
  case "${c%=*}" in
    log-queries )
      logging=1 ;;
    log-facility )
      facility="$r" ;;
    local-ttl )
      ttl="$r" ;;
    conf-file )
      if ! echo $loopcheck | grep "$r" ; then
        readconf "$r"
      fi
      ;;
  esac
done
}

urlDec() {
  echo "$1" | \
    sed 's/+/ /g;s/\%0[dD]//g' | \
    awk '/%/{while(match($0,/\%[0-9a-fA-F][0-9a-fA-F]/)) \
        {$0=substr($0,1,RSTART-1)sprintf("%c",0+("0x"substr($0,RSTART+1,2)))substr($0,RSTART+3);}}{print}'
}

setQueryVars() {
  local vars=${*//\*/%2A}
  local var
  for var in ${vars//&/ }; do
    local value="$( urlDec "${var#*=}savenewlines" )"
    value=$( echo -n "$value" | sed "s/'/\'\"'\"\'/g" )
    eval "cgi_${var%=*}='${value%savenewlines}'"
  done
}

savefile() {
  local v
  if v="$( (echo -n "$cgi_contents" > "$1") 2>&1 )" ; then
    echo -n SUCCESS
  else
    echo "ERROR: $v"
  fi
}

appendfile() {
  local v
  if grep -q '^'"$cgi_contents"'$' $1 ; then
    echo -n SUCCESS
  else
    if v="$( (echo "$cgi_contents" >> "$1") 2>&1 )" ; then
      echo -n SUCCESS
    else
      echo "ERROR: $v"
    fi
  fi
}

pagescript() {
if [ "$edit" = "1" -o "$edit" = "2" ]; then
cat << EOF

  function disableInput(disabled) {
    var inputs = document.getElementsByTagName("a");
    for (var i = 0; i < inputs.length; i++) {
      inputs[i].disabled = disabled;
    }
    var inputs = document.getElementsByTagName("input");
    for (var i = 0; i < inputs.length; i++) {
      inputs[i].disabled = disabled;
    }
    var selects = document.getElementsByTagName("select");
    for (var i = 0; i < selects.length; i++) {
      selects[i].disabled = disabled;
    }
    var textareas = document.getElementsByTagName("textarea");
    for (var i = 0; i < textareas.length; i++) {
      textareas[i].disabled = disabled;
    }
    var buttons = document.getElementsByTagName("button");
    for (var i = 0; i < buttons.length; i++) {
      buttons[i].disabled = disabled;
    }
  }

  function saveText() {
    var xhr = new XMLHttpRequest();
    var urlEncodedData = "";
    var urlEncodedDataPairs = [];
    var filename = this.id.replace("btn_", "");
    var contents = document.getElementById(filename).value;
    var msgElement = document.getElementById("msg_" + filename);
    var msgTimeout = 10000;
    if ( transformSupport() ) { msgTimeout=1000 };

    disableInput(true);
    msgElement.innerHTML="...saving " + filename + "...";
    msgElement.className="busy";

    urlEncodedDataPairs.push( encodeURIComponent("action") + "=" + encodeURIComponent("savefile") );
    urlEncodedDataPairs.push( encodeURIComponent("filename") + "=" + encodeURIComponent(filename) );
    urlEncodedDataPairs.push( encodeURIComponent("contents") + "=" + encodeURIComponent(contents) );

    urlEncodedData = urlEncodedDataPairs.join("&").replace(/%20/g, "+");

    xhr.onreadystatechange=function() {
      if ( xhr.readyState==4 ) {
        if ( xhr.status==200 && xhr.responseText=="SUCCESS") {
          msgElement.innerHTML = "file saved"
          msgElement.className = "success" ;
          document.getElementById(filename).defaultValue=document.getElementById(filename).value;
          setTimeout( function() {msgElement.className="clearmsg"}, msgTimeout )  ;
        } else {
          msgElement.title="ERROR \nState: " + xhr.readyState + "\nStatus: " + xhr.status + \
                           "\nStatus Text:" + xhr.statusText + "\nresponse:\n" + xhr.responseText;
          msgElement.innerHTML="!! ERROR - file not saved !!" ;
          msgElement.className="error" ;
          setTimeout( function() {msgElement.className="clearmsg"}, msgTimeout )  ;
        }
        disableInput(false) ;
      }
    };
    xhr.open("POST", "$scriptname");
    xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
    xhr.setRequestHeader("Content-Length", urlEncodedData.length);
    xhr.send(urlEncodedData);
  }

  function transformSupport() {
    return  ( "transform" in document.body.style);
  }

  function isDirty() {
    if (this.value != this.defaultValue) {
      document.getElementById("msg_" + this.id).innerHTML = "changes are not saved" ;
    } else {
      document.getElementById("msg_" + this.id).innerHTML = "" ;
    }
  }

EOF
else
cat << EOF

  function appendText(contents, filename, element) {
    var xhr = new XMLHttpRequest();
    var urlEncodedData = "";
    var urlEncodedDataPairs = [];

    urlEncodedDataPairs.push( encodeURIComponent("action") + "=" + encodeURIComponent("appendfile") );
    urlEncodedDataPairs.push( encodeURIComponent("filename") + "=" + encodeURIComponent(filename) );
    urlEncodedDataPairs.push( encodeURIComponent("contents") + "=" + encodeURIComponent(contents) );

    urlEncodedData = urlEncodedDataPairs.join("&").replace(/%20/g, "+");

    xhr.onreadystatechange=function() {
      if ( xhr.readyState==4 ) {
        if ( xhr.status==200 && xhr.responseText=="SUCCESS") {
            element.parentNode.className="savedline";
//          alert("File Saved")
        } else {
          element.parentNode.className="errorline";
          alert( "ERROR \nState: " + xhr.readyState + "\nStatus: " + xhr.status + \
                           "\nStatus Text:" + xhr.statusText + "\nresponse:\n" + xhr.responseText );
        }
      }
    };
    xhr.open("POST", "$scriptname");
    xhr.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
    xhr.setRequestHeader("Content-Length", urlEncodedData.length);
    xhr.send(urlEncodedData);
  }

  var count=$REFRESHTIME;
  if (count > 0) {
    var counter=setInterval(timer, 1000);
  }

  function timer()
  {
    count=count-1;
    if ( document.getElementById("timer") ) { document.getElementById("timer").innerHTML = count } ;
    if (count <= 0)
    {
      clearInterval(counter);
      window.location = "$scriptname$NEXTACTION";
      return;
    }
  }

EOF
fi
}

if [ "$REQUEST_METHOD" = "POST" ]; then
  local file=""
  setQueryVars "$(cat)"
  case "$cgi_filename" in
    blacklist)
      file="$blacklist"
      ;;
    whitelist)
      file="$whitelist"
      ;;
    config)
     file="$config"
      ;;
    *)
      echo "Invalid File - $cgi_filename"
      exit
      ;;
  esac

  case "$cgi_action" in
    savefile)
      savefile "$file"
      ;;
    appendfile)
      appendfile "$file"
      ;;
    *)
      echo "Unknown action - $cgi_action"
      ;;
  esac
  exit
fi

ttl=0

readconf $dnsmasq_config

if [ "$facility" != "" ]; then
  dnsmasqlog="$facility"
  dnsmasq_external_log="y"
fi

if [ "$LISTMODE" = "HOST" ]; then
  grepstr="$hostlink"
else
  grepstr="config"
fi

[ "$PIXEL_IP" != "0" ] && pixmsg="retrieving status...<br>" || pixmsg="Pixelserv not enabled - using IP $redirip<br>"

if nslookup $LISTMODE.$modehost 2> /dev/null | grep -q $redirip ; then
  liststatus="up"
else
  liststatus="down"
fi

blocklistcontents=$(	echo "Mode: $LISTMODE"
			echo "blocklist contents - $blocklist"
			head -n5 $blocklist | ( while read line; do echo "    $line"; done )
        		echo "    ..."
        		tail -n2 $blocklist | ( while read line; do echo "    $line"; done )
		     ) 2> /dev/null

ipt=$(iptables -vnL $chain 2> /dev/null)
fwlines=$(iptables -nL $chain 2>/dev/null | wc -l)

if iptables -nL | grep -q "$chain .* $redirip" 2>/dev/null  && [ $fwlines -gt 2 ] ; then
  iptstatus="up - $(( fwlines - 2 )) rules"
else
  iptstatus="down"
fi

if ps | grep -v grep | grep -q "${pixelbin##*"/"} $redirip"; then
  pixstatus="up"
else
  pixstatus="down"
fi

if [ "$logging" = "1" ] ; then
  #logstatus="up"
  logstatus="<a href='$scriptname?dodnsmasqtoggle'>enabled</a>"
else
  #logstatus="down"
  logstatus="<a href='$scriptname?dodnsmasqtoggle'>DISABLED</a>"
fi



optionshtml="<br><a href=$scriptname?force>force</a>
             <br><a href=$scriptname?start>start/update</a>
             <br><a href=$scriptname?restart>restart</a>
             <br><a href=$scriptname?stop>stop</a>
             <br>
             <br><a href=$scriptname?editlists>edit lists</a>
             <br><a href=$scriptname?editconfig>edit config</a>
            "

statushtml="<span title='$blocklistcontents'>
  blocklist: $liststatus
  </span>
  <br><span title=\"$ipt\">iptables: $iptstatus
  </span>
  <br>pixelserv: $pixstatus
  <br>logging: $logstatus
  <br>hosts: $( tail -n1 $blocklist  | grep -oE "[0-9]*")
  <br>ttl: $ttl
"

REFRESHTIME=120
NEXTACTION=""
action=""
actionhtml="<br><i>please wait...</i>"
blockedhosts=""
resolvedhosts=""
blockwidth="100%"
divfocus="#f6f6f6"
focus="blocks"

case $QUERY_STRING in
  dopixstat)
    if [ "$PIXEL_IP" = "0" ]; then
       echo $pixmsg
       exit
    fi
    pixmsg=$(wget -q -t 1 -T 5 -O - "http://$redirip/servstats" 2>/dev/null || echo error)
    if [ "$pixmsg" != "" -a "$pixmsg" != "error" ]; then
      echo $pixmsg
    elif [ "$pixmsg" = "error" ]; then
      echo ERROR: No response from pixelserv.
    else
      echo Running version of pixelserv does not support status reporting.
    fi
    exit
  ;;
  force)
    REFRESHTIME=1;
    NEXTACTION="?doforce";
    statushtml="force updating adblock..."
  ;;
  start)
    REFRESHTIME=1;
    NEXTACTION="?dostart";
    statushtml="starting/updating adblock..."
  ;;
  restart)
    REFRESHTIME=1;
    NEXTACTION="?dorestart";
    statushtml="restarting adblock..."
  ;;
  stop)
    REFRESHTIME=1;
    NEXTACTION="?dostop";
    statushtml="stopping adblock..."
  ;;
  doforce)
    REFRESHTIME=0;
    statushtml="force updating adblock..."
    action="force"
  ;;
  dostart)
    REFRESHTIME=0;
    statushtml="starting/updating adblock..."
    action="start"
  ;;
  dodnsmasqtoggle)
	dnsmasqconf="/etc/dnsmasq.custom"
	if grep -Fxq 'log-queries' $dnsmasqconf
	then
	sed -i 's/\<log-queries\>//g' $dnsmasqconf
	else
	echo 'log-queries' >> $dnsmasqconf
	fi
	service dnsmasq restart
	REFRESHTIME=1;
	;;
  dorestart)
    REFRESHTIME=0;
    statushtml="restarting adblock..."
    action="restart"
  ;;
  dostop)
    REFRESHTIME=0;
    action="stop"
    statushtml="stopping adblock..."
  ;;
  editlists)
    edit="1"
    blacklist_text="$(cat $blacklist 2> /dev/null; echo -n x)"
    blacklist_text="${blacklist_text%x}"
    whitelist_text="$(cat $whitelist 2> /dev/null; echo -n x)"
    whitelist_text="${whitelist_text%x}"
    focus="blacklist"
    divfocus="inherit"
    blockwidth="50%"
    REFRESHTIME=0;
    actionhtml=$optionshtml
  ;;
  editconfig)
    edit="2"
    config_text="$(cat $config 2> /dev/null; echo -n x)"
    config_text="${config_text%x}"
    focus="config"
    divfocus="inherit"
    blockwidth="100%"
    REFRESHTIME=0;
    actionhtml=$optionshtml
  ;;
  *)
    blockwidth="50%"
    actionhtml=$optionshtml
    [ "$logging" = "1" ] && blockedhosts="recently blocked hosts:"
    [ "$logging" = "1" ] && resolvedhosts="recently resolved hosts:"
  ;;
esac

if [ $REFRESHTIME -gt 0 ]; then
  refreshhtml="page will automatically <a href=\"$scriptname\">refresh</a> in <span id=\"timer\">$REFRESHTIME</span> seconds"
else
  refreshhtml="<a href=\"$scriptname\">adblock home</a>"
fi

cat << EOF
<!DOCTYPE html>
<html>
<head>
<title>adblock status</title>

<script>
  $(pagescript)

  function pixstat()
  {
    var xhr=new XMLHttpRequest();
    xhr.onreadystatechange=function()
    {
      if (xhr.readyState==4 && xhr.status==200)
      {
        document.getElementById("pixstat").innerHTML=xhr.responseText;
      } else if (xhr.readyState==4) {
        document.getElementById("pixstat").innerHTML="ERROR: Could not query status<br>";
      }
    }
    xhr.open("GET","$scriptname?dopixstat",true);
    xhr.send();
  }

  window.onload = function() {
        var textareas = document.getElementsByTagName("textarea");
        for (var i = 0; i < textareas.length; i++) {
          textareas[i].onkeyup = isDirty;
          textareas[i].onblur = isDirty;
        }
        var buttons = document.getElementsByTagName("button");
        for (var i = 0; i < buttons.length; i++) {
          buttons[i].onclick = saveText;
        }
	if (document.getElementById("$focus").focus) { document.getElementById("$focus").focus() };
	pixstat() ;
  }

</script>

<style type="text/css">
html {
  background-color: #ffffff;
  height: 100%;
}
body {
  font-size: small;
  font-family: verdana, geneva, sans-serif;
  margin: 0px;
  overflow-y: auto;
}
pre {
  font-family: "Courier New", Courier, monospace;
  font-size: 100%;
}
div {
  outline-width: 0px;
  box-sizing: border-box;
  margin: 0px;
  border-color: #888;
  border-style: solid;
  border-width: 0px;
  padding: 2px;
  display: block;
}
#banner {
  position: fixed;
  width: 100%;
  top: 0px;
  left: 0px;
  height: 150px;
  padding: 0px;
  border-bottom-width: 1px;
  overflow: hidden;
}
#status {
  height: 100%;
  float: left;
  width: 15% ;
  min-width: 120px ;
  max-width: 180px ;
  border-right-width: 1px;
}
#actions {
  height: 100%;
  float: left;
  width: 15% ;
  min-width: 120px ;
  max-width: 150px ;
  border-right-width: 1px;
}
#time {
  height: 100%;
  overflow-y: auto;
}
#blocks {
  position:fixed;
  top: 150px;
  bottom: 0px;
  left: 0px;
  width: $blockwidth;
  overflow: auto;
}
#blocks2 {
  position:fixed;
  top: 150px;
  bottom: 0px;
  right: 0px;
  width: 50%;
  overflow: auto;
 }
#msg_blacklist, #msg_whitelist, #msg_config {
  position:absolute;
  height: 1.6em;
  box-sizing: border-box;
  top: 0px;
  left: 0px;
  right: 0px;
  text-align: center;
  font-weight: bold;
}
#btn_div {
  position: absolute;
  box-sizing: border-box;
  top: 0px;
  right: 0px;
}
#listname {
  position: absolute;
  box-sizing: border-box;
  top: 0px;
  left: 0px;
}
#mytext {
  position:absolute;
  box-sizing: border-box;
  top: 1.5em;
  bottom: 0px;
  left: 0px;
  right: 0px;
}
textarea {
  box-sizing: border-box;
  top: 0px;
  left: 0px;
  resize: none;
  width: 100%;
  height: 99.5%;
  overflow: auto;
  padding: 0.5em;
}
input[type="submit"], button {
  top: 1px;
  padding: 1px 5px 1px 5px;
  position:absolute;
  box-sizing: border-box;
  right: 2px;
}
#whitelist:focus, #blacklist:focus, #config:focus {
  background-color: #f6f6f6;
}
#blocks:focus, #blocks2:focus {
  background-color: $divfocus;
}
.busy {
  background-color: #ffff00;
  transition: background-color .5s ease;
}
.success {
  background-color: #00ff00;
  transition: background-color .5s ease;
}
.error {
  background-color: #ff3333;
  transition: background-color .5s ease;
}
.clearmsg {
  background-color: inherit;
  transition: background-color 7s ease;
}
.line {
}
.savedline {
  color: green;
  font-weight: bold;
  transition: color .4s ease;
}
.errorline {
  color: red;
  font-weight: bold;
  transition: color .4s ease;
}
.line:hover, .errorline:hover {
  color: blue;
  font-weight: bold;
}
.line:hover .add , .errorline:hover .add {
  display: inline;
}
.add {
  display: none;
  cursor: pointer;
}

</style>
</head>

<body>
<div id="banner">
  <div id="status">
    <b>adblock status:</b><br>
    <span id="statustxt">
      $statushtml
   </span>
  </div>

  <div id="actions">
    <b>adblock actions:</b>
    <span id="actiontxt">
      $actionhtml
    </span>
  </div>

  <div id="time">
    <b>time info:</b><br>
    $(uptime)
    <br><br><b>pixelserv info:</b>
    <br><span id="pixstat">$pixmsg</span>
    <br><br>$refreshhtml
  </div>
</div>
EOF


if [ "$action" != "" ] ; then
  [ "$action" = "start" ] && cmdaction="" || cmdaction=$action
  echo '<div id="blocks"><pre>'
  $adblockscript $cmdaction
  echo "</pre><p></div>
        <script>
          document.getElementById(\"statustxt\").innerHTML=\"$action complete\";
          document.getElementById(\"actiontxt\").innerHTML=\"$(echo $optionshtml)\";
        </script>
     </body></html>"
  exit
fi


if [ "$edit" = "1" ]; then
echo '
  <div id="blocks">
    <div id="msg_blacklist"></div>
    <div id="listname"><b title="'"$blacklist"'">blacklist</b></div>
    <button type="button" id="btn_blacklist" tabindex="20">save
    </button>
    <div id="mytext">
      <textarea  id="blacklist" wrap="off" tabindex="10" accesskey="b">'"$blacklist_text"'</textarea>
    </div>
  </div>

  <div id="blocks2">
    <div id="msg_whitelist"></div>
    <div id="listname"><b title="'"$whitelist"'">whitelist</b></div>
    <button type="button" id="btn_whitelist" tabindex="40">save
    </button>
    <div id="mytext">
      <textarea  id="whitelist" wrap="off" tabindex="30" accesskey="b">'"$whitelist_text"'</textarea>
    </div>
  </div>
</body>
</html>
'
exit
fi

if [ "$edit" = "2" ]; then
echo '
  <div id="blocks">
    <div id="msg_config"></div>
    <div id="listname"><b title="'"$config"'">config</b></div>
    <button type="button" id="btn_config" tabindex="20">save
    </button>
    <div id="mytext">
      <textarea  id="config" wrap="off" tabindex="10" accesskey="b">'"$config_text"'</textarea>
    </div>
  </div>
</body>
</html>
'
exit
fi

cat << EOF
  <div id="blocks" accesskey="b" tabindex="1">
    <span title="$dnsmasqlog">
    $blockedhosts </span>
    <pre>$( [ "$REFRESHTIME" != "1" ] && egrep -hB1 "$grepstr .* is $redirip" $dnsmasqlog* | \
            egrep 'query.* from ' | grep -v 'from 127.0.0.1' | tail -n 100 | sed 's|^\(.*:..:..\) .*: quer|\1 |' | \
            awk '{printf("<span class=\"line\">%s %s %s %-13s %s <span title=\"add %s to whitelist\" class=\"add\" onclick=\"appendText(\x27%s\x27, \x27whitelist\x27, this);\">\[+w]</span></span>\n", $1,$2,$3,$7,$5,$5,$5)}'  | \
            sort -r )
    </pre>

  </div>
  <div id="blocks2" accesskey="r" tabindex="1">
     $resolvedhosts <br>
    <pre>$( [ "$REFRESHTIME" != "1" ] &&  tail -n 4000 $dnsmasqlog | grep  "reply .* is .*"  | grep -v "NODATA\|NXDOMAIN" | sort -r | sed   's/.* reply \(.*\) is .*/\1/p' | awk '!a[$0]++' | tail -n 100 | \
            awk '{printf("<span class=\"line\">%s <span title=\"add %s to blacklist\" class=\"add\" onclick=\"appendText(\x27%s\x27, \x27blacklist\x27, this);\">\[+b]</span></span>\n", $1,$1,$1)}' )
    </pre>
  </div>
</body>
</html>
EOF