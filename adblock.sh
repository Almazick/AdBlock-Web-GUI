#!/bin/sh

## Modified from Clean, Lean and Mean Adblock v4.5 by haarp
##
## http://www.linksysinfo.org/index.php?threads/script-clean-lean-and-mean-adblocking.68464/
##
## Use at your own risk
##
## See adblock.readme for release notes
##

#########################################################
#							#
# Static values - these cannot / should not be changed  #
# in the config file.					#
#							#
#########################################################

umask 0022

alias iptables='/usr/sbin/iptables'
alias nslookup='/usr/bin/nslookup'
alias ls='/bin/ls'
alias df='/bin/df'
alias ifconfig='/sbin/ifconfig'

pidfile=/var/run/adblock.pid

release="2015-11-11"

# buffer for log messages in cgimode or firemode
msgqueue=""

# router memory
ram=$(awk '/^MemTotal/ {print int($2/1024)}' < /proc/meminfo)

# this script
me="$(cd $(dirname "$0") && pwd)/${0##*/}"

# Is this run as CGI?
[ -n "$REQUEST_METHOD" ] && cgimode=1

[ "${me##*"."}" = "fire" ] && firemode=1

# path to script -  was script called via an autorun link?
if [ "${me##*"."}" = "fire" -o "${me##*"."}" = "wanup" -o  "${me##*"."}" = "shut" ]; then
	# yes - find true script folder
 	s="$( ls -l "$me" )"; s="${s##*" -> "}"
	binprefix="$(cd "$(dirname "$me")" && cd "$(dirname "$s")" && pwd)"
	adblockscript="$binprefix/${s##*"/"}"
	islink=1
elif [ -L $me -a "$cgimode" = "1" -a -e $me.weblink ]; then
	# called via a link, we are in cgi environment, and weblink file exists
	# so follow the link for binprefix location
	s="$( ls -l "$me" )"; s="${s##*" -> "}"
	binprefix="$(cd "$(dirname "$me")" && cd "$(dirname "$s")" && pwd)"
	adblockscript="$binprefix/${s##*"/"}"
	islink=1
else
	# no -  use folder of $me
	binprefix="$(dirname "$me")"
	adblockscript="$me"
	islink=0
fi

# base name to use when looking for config files
configname=adblock

# legacy config file
config=$binprefix/config

# list of config files to look for if legacy file is missing
# use a fully pathed name if custonizing
# first match found wins
ini="$configname.ini"
configlist="$binprefix/$ini
  $binprefix/$configname/$ini
  /jffs/$configname/$ini
  /jffs/etc/$ini
  /jffs/$ini
  /opt/$configname/$ini
  /opt/etc/$ini
  /opt/$ini
  /mmc/$configname/$ini
  /mmc/etc/$ini
  /mmc/$ini
  /cifs1/$configname/$ini
  /cifs1/etc/$ini
  /cifs1/$ini
  /cifs2/$configname/$ini
  /cifs2/etc/$ini
  /cifs2/$ini
  /tmp/$configname/$ini
  /tmp/$ini
"
#########################################################
# End of static values					#
#########################################################


#########################################################
#							#
# Default values - can be changed in config file.	#
#							#
#########################################################

# path to list files
prefix=$binprefix

# pixelserv executable
pixelbin=$binprefix/pixelserv

# temp folder for stripped white/blacklist
tmp=/tmp

# what to consider a small disk in MB
smalldisk=64

# what to consider a small tmp folder in MB
smalltmp=24

# firewall autorun script
fire=/etc/config/99.adblock.fire

# wanup autorun script
wanup=/etc/config/99.adblock.wanup

# shutdown autorun script
shut=/etc/config/00.adblock.shut

# hosts file link
hostlink=/etc/dnsmasq/hosts/zzz.adblock.hosts

# virtual interface name, should be unique enough to avoid grep overmatching
vif=adblk

# iptables chain name, should be unique enough to avoid grep overmatching
chain=adblk.fw

# testhost
testhost="adblock.is.loaded"

# modehost
modehost="mode.is.loaded"

# listtmp set to /tmp folder for blocklist generation to reduce writes to jffs/usb if more than 64MB ram
# defaults to previous behavior if less ram, or can be set explicitly in config
listtmp=""

# list of generated source files
sourcelistfile=$tmp/sourcelist.$$.tmp

# default cron schedule standard cru format
schedule="10 02 * * *"
cronid=adblock.update

# minimum age of blocklist in hours before we re-build
age2update=4

# symlink for web interface
weblink=/www/user/adblock.sh

# script for web interface
webscript=adblockweb.sh

# Add Adblock link to Tomato GUI
tomatolink=1

# don't output log for cgi wrapper mode
quietcgi=1

# don't output log for firewall mode
quietfire=1

# path to dnsmasq.conf
dnsmasq_config="/etc/dnsmasq.conf"

# enable logging - a value of "1" will add "log-queries" to $CONF
# and restart dnsmasq if necessary
#
# has no effect if logging is already enabled in dnsmasq.conf
dnsmasq_logqueries=""

# !**** CAUTION ****!
# dnsmasq_custom - use at your own risk
#
# value will be appended to $CONF as entered
#
# example:
# dnsmasq_custom='
# log-facility=/tmp/mylogfile
# log-dhcp
# log-queries
# local-ttl=600
# '
#
# !! do not use unless you know what you are doing !!
#
# dnsmasq is very sensitive and will not start with invalid entries, entries
# that conflict with directives in the primary config, and some duplicated
# entries
#
# no validation of the content is performed by adblock
#
# !**** CAUTION ****!
dnsmasq_custom=""

# additional options for wget
wget_opts=""

# list mode
LISTMODE="OPTIMIZE"

# default to using primary lan interface
BRIDGE="$(nvram get lan_ifname)"

# default to strict firewall rules
FWRULES=STRICT

# default interface(s) for firewall rules
# supports multiple interfaces as well, ie: "br0 br1 br3"
FWBRIDGE="br+ lo"

# set haarp config defaults - config file overrides
# 0: disable pixelserv, 1-254: last octet of IP to run pixelserv on
PIXEL_IP=254

# let system determin pixelserv ip based on PIXEL_IP and existing
redirip=""

# additional options for pixelserv
PIXEL_OPTS=""

# 1: keep blocklist in RAM (e.g. for small JFFS)
RAMLIST=0

# dnsmasq custom config (must be sourced by dnsmasq!) confused? then leave this be!
CONF=/etc/dnsmasq.custom

# whitelist and blacklist contents
BLACKLIST=""
WHITELIST=""


#########################################################
# End of default values					#
#########################################################

elog() {
 local tag="ADBLOCK[$$]"
 local myline
 local pad="                    "
 local len=${2:-"0"}
 pad=${pad:0:$len}

 local p1=${1:-"-"}

 [ "$cgimode" = "1" -o "$firemode" = "1" ] && {
   [ "$p1" = "-" ] &&  {
     [ -t 0 ] || while read myline; do msgqueue="$msgqueue""$pad$myline\n" ; done
   } || msgqueue="$msgqueue""$pad$p1\n"
 } || {
   [ "$p1" = "-" ] && {
     [ -t 0 ] || while read myline; do logger -st "$tag" "$pad$myline"; done
   } || logger -st "$tag" "$pad$p1"
 }
}

flushlog() {
# display queue and disable cgi/fire modes
 [ "$msgqueue" != "" ] && {
	cgimode=0
	firemode=0
	[ "$msgqueue" != "" ] && echo -ne "$msgqueue" | elog
	msgqueue=""
 }
}

pexit() {
	flushlog
	elog "Exiting $me $@"
	rm -f "$pidfile" &>/dev/null
	logvars2
	exit $@
}

logfw() {
	elog "iptables"
	{ echo -e "filter\n========================================================================"
	  iptables -vnL
	  echo -e "\nnat\n========================================================================"
	  iptables -vnL -t nat
	  echo -e "\nmangle\n========================================================================"
          iptables -vnL -t mangle
	} | elog - 4
}

logvars() {
	[ "$debug" != "1" ] && return
	elog "Running on $( nvram get os_version )"
	elog "PID  $(ps -w | grep $$ | grep -v grep) SHLVL $SHLVL"
	elog "PPID $(ps -w | grep $PPID | grep -v grep)"
	elog "Initialized Environment:"
	set | elog - 4
	elog "Mounted Drives"
	mount | elog - 4
	elog "Free Space"
	df -h | elog - 4
	elog "prefix folder - $prefix"
	ls -lh $prefix | elog - 4
	elog "listprefix folder - $listprefix"
	ls -lh $listprefix | elog - 4
	elog "listtmp folder - $listtmp"
	ls -lh $listtmp | elog - 4
	elog "config file contents - $config"
	cat $config | elog - 4
	logfw
}

logvars2() {
	[ "$debug" != "1" ] && return
	elog "Environment at exit:"
	elog "Free Space"
	df -h | elog - 4
	elog "prefix folder - $prefix"
	ls -lh $prefix | elog - 4
	elog "listprefix folder - $listprefix"
	ls -lh $listprefix | elog - 4
	elog "listtmp folder - $listtmp"
	ls -lh $listtmp | elog - 4
	elog "blocklist contents - $blocklist"
	head $blocklist | elog - 4
	elog "    ..."
	tail -n2 $blocklist | elog - 4
	elog "CONF contents - $CONF"
	cat $CONF | elog - 4
	logfw
}

readdnsmasq() {
	[ "$3" != "r" ] && loopcheck=""
	loopcheck="$loopcheck ""$1"
	for c in $( head -n 100 $1 | sed 's/#.*$//g' | sed -e 's/^[ \t]*//' 2> /dev/null )
	do
		l="${c%=*}"
		r="${c#*=}"
		case "$l" in
		$2 )
		echo "$r"
      		;;
		conf-file )
		if ! echo $loopcheck | grep "$r " ; then
			readdnsmasq "$r" "$2" "r"
		fi
		;;
		esac
	done
}

startserver() {
	if [ "$PIXEL_IP" != "0" ]; then
		if ! ifconfig | grep -q $BRIDGE:$vif; then
			elog "Setting up $rediripandmask on $BRIDGE:$vif"
			ifconfig $BRIDGE:$vif $rediripandmask up
		fi
		if ps -w | grep -v grep | grep -q "${pixelbin##*"/"} $redirip"; then
			elog "pixelserv already running, skipping"
		else
			elog "Setting up pixelserv on $redirip"
			"$pixelbin" $redirip $PIXEL_OPTS 2>&1 | elog
		fi
		# create autorun links
		[ -d /etc/config ] || mkdir /etc/config
		[ $islink = 0 ] && ln -sf "$me" "$fire"
		[ $islink = 0 ] && ln -sf "$me" "$shut"
	else
		# something odd has happened if we need this, but better safe...
		rm -f "$fire" &>/dev/null
		rm -f "$shut" &>/dev/null
		stopserver
	fi
	fire
}

stopserver() {
	killall pixelserv
	ifconfig $BRIDGE:$vif down
} &> /dev/null

rmfiles() {
	{
		rm -f "$fire"
		rm -f "$shut"
		rm -f "$hostlink"
		rm -f "$tmpstatus"
	} &>/dev/null
	CONFchanged=0
	if [ -e "$CONF" ]; then
		local CONFmd51=$(md5sum "$CONF" 2>/dev/null)
		echo -n > "$CONF"
		local CONFmd52=$(md5sum "$CONF" 2>/dev/null)
		if [ "$CONFmd51" = "$CONFmd52" ]; then
			elog "CONF file $CONF unchanged"
		else
			CONFchanged=1
			elog "CONF file $CONF truncated"
		fi
	fi
}

stop() {
	elog "Stopping"
	rmfiles
	stopserver
	cleanfire
	restartdns
	currentmode="OFF"
}

restartdns() {
	[ $LISTMODE = "HOST" ] &&  [ "$logging" = "$dnsmasq_logqueries" ] && [ "$CONFchanged" != "1" ] && {
		[ $currentmode = "HOST" -o $currentmode = "OFF" ] && {
			elog "Loading hosts file for dnsmasq"
			kill -HUP $( pidof dnsmasq )
			return
		}
	}
	elog "Restarting dnsmasq"
	service dnsmasq restart | elog
}

writeconf() {

	[ ! -e "$CONF" ] &&  echo -n > "$CONF"

	local CONFmd51=$(md5sum "$CONF" 2>/dev/null)
	echo -n > "$CONF"

	if [ ! -f $blocklist  -o ! -s $blocklist ]; then
		elog "Blocklist Missing or empty - REMOVING DNSMASQ FILES / ADBLOCK MAY BE DISABLED!"
		rm -f "$hostlink" &>/dev/null
		return
	fi

	if [ $LISTMODE = "HOST" ] ; then
		elog "Creating Hosts File Link $hostlink"
		if ! ln -sf "$blocklist" "$hostlink" ; then
			elog "Could not create host file link $hostlink"
			rm -f "$hostlink" &>/dev/null
			return
		fi
	else
		elog "Writing File $CONF"
		rm -f "$hostlink" &>/dev/null
		echo "conf-file=$blocklist" >> "$CONF"
	fi

	# enable logging if needed
	[ "$dnsmasq_logqueries" = "1" ] && echo "log-queries" >> "$CONF"

	# add custom dnsmasq settings
	[ "$dnsmasq_custom" != "" ] && echo "$dnsmasq_custom" >> "$CONF"

	local CONFmd52=$(md5sum "$CONF" 2>/dev/null)
	if [ "$CONFmd51" = "$CONFmd52" ]; then
		CONFchanged=0
		elog "CONF file $CONF unchanged"
	else
		CONFchanged=1
		elog "CONF file $CONF changed"
	fi
}

cleanfiles() {
	cru d $cronid
	stop
	elog "Cleaning files"
	rm -f $prefix/lastmod-* &> /dev/null
	rm -f $prefix/source-* &> /dev/null
	rm -f $tmpstatus &> /dev/null
	rm -f $blocklist  &> /dev/null
	rm -f $weblink  &> /dev/null
	rm -f $weblink.weblink  &> /dev/null
	rmtomatolink
	elog "The following files remain for manual removal:"
	ls -1Ad $me $config $listprefix/* $prefix/* 2>/dev/null| sort -u | elog - 4
}

shutdown() {
	rmfiles
	stopserver
}

fire() {
	cleanfire

	# Nothing to do if not running pixelserv
	[ "$PIXEL_IP" = "0" ] && return

	[ "$FWRULES" = "NONE" ] && return

	[ $(( $(nvram get log_in) & 1 )) = 1 ] && {
		drop=logdrop
		logreject=1
		limit=$(nvram get log_limit)
		[ $limit = 0 ] && limitstr="" || limitstr=" -m limit --limit $limit/m "
	} || {
		drop=DROP
		logreject=0
	}

	[ $(( $(nvram get log_in) & 2 )) = 2 ] && accept=logaccept || accept=ACCEPT

	vpnline=$( iptables --line-numbers -vnL INPUT | grep -Em1  "ACCEPT .* all.*(tun[0-9]|tap[0-9]).*0.0.0.0.*0.0.0.0/0" | cut -f 1 -d " ")
	stateline=$(iptables --line-numbers -vnL INPUT | grep -m1 "ACCEPT.*state.*RELATED,ESTABLISHED" | cut -f 1 -d" ")
	[ "$vpnline" != "" ] && [ "$vpnline" -lt "$stateline" ] && inputline="" || inputline=$(( stateline + 1 ))
	iptables -N $chain
	iptables -I INPUT $inputline -d $redirip -j $chain
	iptables -A $chain -m state --state INVALID -j DROP
	iptables -A $chain -m state --state RELATED,ESTABLISHED -j ACCEPT
	for i in $FWBRIDGE; do
		netstat -ltn | grep -q "$redirip:443" && {
			# we are listening for ssl, so let both 80 and 443 through
			iptables -A $chain -i $i -p tcp -m multiport --dports 443,80 -j $accept
		} || {
			# else only allow port 80 and redirect 443 (assumes pixelserv v32 or later)
			iptables -A $chain -i $i -p tcp --dport 80 -j $accept
			# comment following lines if v31 or earlier
			iptables -t nat -nL $chain &>/dev/null || {
				iptables -t nat -N $chain
				iptables -t nat -A PREROUTING -p tcp -d $redirip --dport 443 -j $chain
			}
			iptables -t nat -A $chain -i $i -p tcp -d $redirip --dport 443 -j DNAT --to $redirip:80
		}
		iptables -A $chain -i $i -p icmp --icmp-type echo-request  -j $accept
		[ $logreject = 1 ] && iptables -A $chain -i $i $limitstr -j LOG --log-prefix "REJECT " --log-macdecode --log-tcp-sequence --log-tcp-options --log-ip-option
		iptables -A $chain -i $i -p tcp -j REJECT --reject-with tcp-reset
		iptables -A $chain -i $i -p all -j REJECT --reject-with icmp-host-prohibited
	done
	[ "$FWRULES" = "STRICT" ] &&  iptables -A $chain -j $drop
}

rmtomatolink() {
	if grep -q "/www/tomato.js" /proc/mounts ; then
		if [ -f "$jsflag" ]; then
			umount /www/tomato.js
		else
			elog "tomatos.js was mounted by something else"
			mountjs=0
		fi
	fi
	rm -f "$jsfile"
	rm -f "$jsflag"
}

addtomatolink() {
	if [ "$tomatolink" = "1" ]; then
		mountjs=1
		if [ "$web_dir" != "" ] && [ "$web_dir" != "default" ]; then
			elog "Skip adding tomato link, non default web_dir($web_dir)"
			mountjs=0
		elif ! grep -q "'log.asp'] ] ],$" /www/tomato.js ; then
			elog "Skip adding tomato link, could not find insertion point in tomato.js"
			mountjs=0
		fi
		rmtomatolink
		if [ "$mountjs" = "1" ]; then
			elog "Adding tomato menu item"
			sed "/'log.asp'] ] ],$/ a  ['Adblock', '${weblink#*/www/}\" target=\"adblock\"']," /www/tomato.js > "$jsfile"
			mount -o bind  "$jsfile" /www/tomato.js
			touch "$jsflag"
		fi
	else
		rmtomatolink
	fi
}

cleanfire() {
	iptables -D INPUT "0$( iptables --line-numbers -vnL INPUT | grep -Fm1 "$chain" | cut -f 1 -d " ")" &>/dev/null
	iptables -F $chain &>/dev/null
	iptables -X $chain &>/dev/null

	iptables -t nat -D PREROUTING "0$( iptables --line-numbers -t nat -vnL PREROUTING | grep -Fm1 "$chain" | cut -f 1 -d " ")" &>/dev/null
	iptables -t nat -F $chain &>/dev/null
	iptables -t nat -X $chain &>/dev/null
}

grabsource() {
	local host=$(echo $1 | awk -F"/" '{print $3}')
	local path=$(echo $1 | awk -F"/" '{print substr($0, index($0,$4))}')
	local lastmod=$(echo -e "HEAD /$path HTTP/1.1\r\nHost: $host\r\n\r\n" | nc -w30 $host 80 | tr -d '\r' | grep "Last-Modified")

	local lmfile="$listprefix/lastmod-$(echo $1 | md5sum | cut -c 1-8)"
	local sourcefile="$listprefix/source-$(echo $1 | md5sum | cut -c 1-8)"
	local sourcesize=$(ls -l "$sourcefile" 2>/dev/null | awk '{ print int(($5/1024/1024) + 0.5) }')
	local freedisk=$(df "$prefix" | awk '!/File/{print int($4/1024)}')

	[ "$force" != "1" -a -f "$sourcefile" -a -n "$lastmod" -a "$lastmod" = "$(cat "$lmfile" 2>/dev/null)" ] && {
		elog "Unchanged: $1 ($lastmod)"
		echo -n "$sourcefile " >> "$sourcelistfile"
		echo 2 >>"$tmpstatus"
		return 2
	}

	# delete the source file we are replacing if larger than free space
	[ -s "$sourcefile" ] && [ "$freedisk" -le "$(( sourcesize + 1 ))" ] && {
		elog "removing $sourcefile size:$sourcesize free:$freedisk"
		rm -f "$sourcefile" &>/dev/null
	}

	elog "Downloading: $1"
	{
		if wget  $1 -O - $wget_opts ; then
			elog "Completed: $1"
			echo 0 >>"$tmpstatus"
		else
			elog "Failed: $1"
			echo 1 >>"$tmpstatus"
		fi
	} | tr -d "\r" | sed -e '/^[[:alnum:]:]/!d' | awk '{print $2}' | sed -e '/^localhost$/d' > "$sourcefile.$$.tmp"

	if [ -s "$sourcefile.$$.tmp" ]  ; then
		[ -n "$lastmod" ] && echo "$lastmod" > "$lmfile"
		mv -f "$sourcefile.$$.tmp" "$sourcefile"
		echo -n "$sourcefile " >> "$sourcelistfile"
	else
		rm -f "$sourcefile.$$.tmp" &>/dev/null
	fi
}

buildlist() {
	elog "Download starting"

	tmpstatus=$tmp/status.$$.tmp

	until ping -q -c1 google.com >/dev/null; do
		elog "Waiting for connectivity..."
		sleep 30
	done

	trap 'elog "Signal received, cancelling"; rm -f "$listprefix"/source-* "$listprefix"/lastmod-* "$tmpstatus" &>/dev/null; pexit 130' SIGQUIT SIGINT SIGTERM SIGHUP

	echo -n "" > "$tmpstatus"
	echo -n "" > "$sourcelistfile"
	for s in $SOURCES; do
		grabsource $s &
	done
	wait

	while read ret; do
		case "$ret" in
			0)	downloaded=1;;
			1)	failed=1;;
			2)	unchanged=1;;
		esac
	done < "$tmpstatus"
	rm "$tmpstatus"

	sourcelist=$(cat "$sourcelistfile")
	rm -f "$sourcelistfile" &>/dev/null

	trap - SIGQUIT SIGINT SIGTERM SIGHUP

	if [ -z "$sourcelist" ] && [ -n "$BLACKLIST" -o -s "$blacklist" ]; then
		elog "Processing blacklist only"
		confgen
	elif [ -z "$sourcelist" ]; then
		elog "No source files found"
		pexit 3
	elif [ "$downloaded" = "1" ]; then
		elog "Downloaded"
		confgen
	elif [ "$unchanged" = "1" ]; then
		elog "Filters unchanged"
		if [ ! -f "$blocklist" -o ! -s "$blocklist" ]; then
			elog "Blocklist does not exist"
			confgen
		elif [ "$LISTMODE" != "$currentmode" -a "$currentmode" != "OFF" ]; then
			elog "Mode changed"
			confgen
		elif [ "$LISTMODE" = "$currentmode" ]; then
			elog "Mode unchanged"
			# no changes to list and already running in current mode
			writeconf # re-write conf or link if needed
			# if no dnsmasq_custom changes, nothing else to do, so exit
			[ "$CONFchanged" = "0" ] && pexit 2
		fi
	else
		elog "Download failed"
		if [ -s "$blocklist" ] && [ ! -f "$CONF" -o ! -s "$CONF" -o  "$logging" != "$dnsmasq_logqueries" -o "$dnsmasq_custom" != "" ]; then #needlink
			:
		else pexit 3
		fi
	fi
}

confgen() {
	cg1=$(date +%s)
	elog "Generating $blocklist - $LISTMODE mode"
	tmpwhitelist="$tmp/whitelist.$$.tmp"
	tmpblocklist="$listtmp/blocklist.$$.tmp"

  	trap 'elog "Signal received, cancelling"; rm -f "$tmpwhitelist" "$tmpblocklist"  &>/dev/null; echo -n "" > "$blocklist"; pexit 140' SIGQUIT SIGINT SIGTERM SIGHUP

	{
		# only allow valid hostname characters
		echo "[^a-zA-Z0-9._-]+"

		if [ -f "$whitelist" ]; then
			# strip comments, blank lines, spaces and carriage returns from whitelist
			sed -e 's/#.*$//g;s/^[ |\t|\r]*//;/^$/d' "$whitelist" 2>/dev/null
		fi

		# add config file whitelist entries to temp file
		for w in $WHITELIST; do
			echo $w
		done

	}  > "$tmpwhitelist"

	{
		# use sourcefiles list (and not all files in folder which could have old/unwanted files)
		[ -n "$sourcelist" ] && cat $sourcelist | grep -Ev -f "$tmpwhitelist"

		rm -f "$tmpwhitelist" &>/dev/null

		[ -f "$blacklist" ] && {
			# strip comments, blank lines, spaces and carriage returns from blacklist
			sed -e 's/#.*$//g;s/^[ |\t|\r]*//;/^$/d' "$blacklist" 2>/dev/null
		}
		for b in $BLACKLIST; do
			echo "$b"
		done

		# add hosts to test if adblock is loaded
		echo $testhost

		echo $LISTMODE.$modehost

	}  > "$tmpblocklist"

	{
		# add header to blocklist, used to determine what mode the list was built for
		# do not alter format without adjusting the grep regex that tests the mode/ip
		echo "# adblock blocklist, MODE=$LISTMODE, IP=$redirip, generated $(date)"

		case $LISTMODE in
			HOST)
				sort -u  "$tmpblocklist" |
				sed -e "s:^:$redirip :"
			;;
			OPTIMIZE)
				sed -e :a -e 's/\([^\.]*\)\.\([^\.]*\)/\2#\1/;ta'  "$tmpblocklist" | sort |
  				awk -F '#' 'BEGIN{d = "%"} { if(index($0"#",d)!=1&&NF!=0){d=$0"#";print $0;} }' |
				sed -e :a -e 's/\([^#]*\)#\([^#]*\)/\2\.\1/;ta' -e "s/\(.*\)/address=\/\1\/$redirip/"
			;;
			LEGACY)
				sort -u  "$tmpblocklist" |
				sed  -e '/^$/d'  -e  "s/\(.*\)/address=\/\1\/$redirip/"
			;;
		esac
		hostcount=$(( $(wc -l < "$blocklist") - 1 ))
		echo "# $hostcount records"

 		rm -f "$tmpblocklist" &>/dev/null
		elog "Blocklist generated - $(( $(date +%s) - cg1 )) seconds"
		elog "$hostcount unique hosts to block"
	}  > "$blocklist"

  	trap -  SIGQUIT SIGINT SIGTERM SIGHUP

}

loadconfig() {
	ignoredlist=""
	configfound="0"

	# look for haarp config file, but since "config" is so generic
	# do at least a minimal check with grep on the contents
	[ -f $config ] && grep -q "SOURCES=" $config && {
		# haarp legacy single folder mode
		# everything defaults to the script location
		configfound="1"
	}
	# if haarp legacy config does not exist, try to find another file
	for c in $configlist; do
		[ -f $c -a "$configfound" = "0" ] && grep -q "SOURCES=" $c && {
			cfolder=$(dirname $c)
			# if config is already in a folder named "adblock" use it, otherwise create an adblock subfolder
			[ "${cfolder##*"/"}" = "$configname" ] && prefix=$cfolder || prefix=$cfolder/$configname
			config=$c
			configfound=1
		} || {
			[ -f $c ] && ignoredlist="$ignoredlist $c"
		}
	done

	elog "Using config file $config"

	# Warn other files were found but ignored
	for c in $ignoredlist; do
		elog "Ignoring extra config file $c"
	done

	[ -f "$config" ] || {
		elog "$config not found!"
		pexit 11
	}

	grep -q "SOURCES=" "$config" || {
		elog "$config does not seem valid!"
		pexit 11
	}

	# silently check for/create prefix folder
	# but don't exit yet if we fail - we may redefine in config
	[ -d "$prefix" ] || {
		mkdir "$prefix" &>/dev/null
		oldprefix=$prefix
		createdprefix=1
	}

	#ensure tthe correct path
	cd "$prefix" &>/dev/null

	# load config
	source "$config"

	# if we created the prefix folder, but aren't using it, remove it.
	[ "$prefix" != "$oldprefix" -a "$createdprefix" = "1" ] && rmdir "$oldprefix" &> /dev/null

	# check prefix folder again - exit on fail this time
	[ -d "$prefix" ] || mkdir "$prefix" || {
		elog "Prefix folder ($prefix) does not exist and cannot be created"
        	pexit 12
	}

	#ensure tthe correct path
	cd "$prefix" &>/dev/null

	if [ "$PIXEL_IP" = "0" ]; then
		[ "$redirip" = "" ] && redirip="0.0.0.0"
	else
		[ "$redirip" = "" ] || {
			elog "PIXEL_IP should be \"0\" if redirip is set in config!"
			pexit 10
		}
		[ -x "$pixelbin" ] || {
			elog "$pixelbin not found/executable!"
			pexit 10
		}
	fi

	#########################################################
	# redirip can be explicitly set in the config file,	#
	# but make sure it is valid as no checks are done	#
	#							#
	# PIXEL_IP still needs to be set to non-zero for 	#
	# pixelserv to be started				#
	#########################################################
	[ "$redirip" = "" ] && {
		rediripandmask=$(ifconfig $BRIDGE | awk -F ' +|:' '/inet addr/{sub(/[0-9]*$/,'$PIXEL_IP',$4); print $4" netmask "$8}')
		redirip=${rediripandmask%% *}
	}

	# $FWRULES must be NONE, LOOSE, or STRICT, if value is unknown, default to STRICT
	FWRULES=$(echo $FWRULES | tr "[a-z]" "[A-Z]")
	echo $FWRULES | grep -Eq "(^NONE$|^LOOSE$|^STRICT$)" || {
		elog "Unknown FWRULES value ($FWRULES), using STRICT settings"
		FWRULES="STRICT"
	}

	# $LISTMODE must be LEGACY, OPTIMIZE, or HOST, if value is unknown, default to OPTIMIZE
	LISTMODE=$(echo $LISTMODE | tr "[a-z]" "[A-Z]")
	echo $LISTMODE | grep -Eq "(^LEGACY$|^OPTIMIZE$|^HOST$)" && {
		elog "Requested list mode is $LISTMODE"
	} || {
		elog "Unknown LISTMODE value ($LISTMODE), using OPTIMIZE settings"
		LISTMODE="OPTIMIZE"
	}

	if [ "$RAMLIST" = "1" ]; then
		listprefix="/var/lib/adblock"
	else
		listprefix="$prefix"
	fi

	[ -d "$listprefix" ] || mkdir "$listprefix" || {
		elog "Blocklist folder ($listprefix) does not exist and cannot be created"
		pexit 12
	}

	freedisk=$(df "$prefix" | awk '!/Filesys/{print int($4/1024)}')
	freetmp=$(df "$tmp" | awk '!/Filesys/{print int($4/1024)}')
	# if listtmp hasn't been explicitly set and more than $smalltmp available on /tmp
	if [ "$listtmp" = "" -a "$freetmp" -gt "$smalltmp" ]; then
		# use /tmp for temp blocklist file
		listtmp=$tmp
	elif [ "$listtmp" = "" ]; then
		# if not set, default to legacy behavior for compatibility
		listtmp="$listprefix"
	else
		# if specified in config, make sure it's there
		[ -d "$listtmp" ] || mkdir "$listtmp" || {
			elog "Blocklist temp folder ($listtmp) does not exist and cannot be created"
			pexit 12
		}
	fi

	if [ "$dnsmasq_logqueries" = "1" ]; then
		elog "Enabling dnsmasq logging"
	fi

	if [ "$(readdnsmasq "$dnsmasq_config" "log-queries")" != "" ]; then
		logging=1
		elog "Logging previously enabled"
	fi

	dnslogfile="$(readdnsmasq "$dnsmasq_config" "log-facility")"
	if [ "$dnsmasq_logqueries" = "1" -o "$logging" = "1" ]; then
		if [ "$dnslogfile" = "" ]; then
			if [ "$(nvram get log_file)" = 1 ]; then
				elog "Logging to syslog"
			else
				elog "Warning: dnsmasq logging to syslog, but syslog is disabled"
			fi
		else
			elog "Logging to $dnslogfile"
		fi
	fi

	jsfile="$(dirname $weblink)/tomato.js.adblock"
	jsflag="$jsfile.mount"
	web_dir="$(nvram get web_dir)"

	currentmode=OFF
	nslookup $testhost &>/dev/null  && currentmode=UNKNOWN
	nslookup host.$modehost &>/dev/null && currentmode=HOST
	nslookup legacy.$modehost &>/dev/null && currentmode=LEGACY
	nslookup optimize.$modehost &>/dev/null && currentmode=OPTIMIZE

	blocklist="$listprefix/blocklist"
	whitelist="$prefix/whitelist"
	blacklist="$prefix/blacklist"

	thisconfig="$config:$(date -r "$config" 2>/dev/null)"
	thisconfig="$thisconfig|$whitelist:$(date -r "$whitelist" 2>/dev/null)"
	thisconfig="$thisconfig|$blacklist:$(date -r "$blacklist" 2>/dev/null)"
	thisconfig="$thisconfig|$adblockscript:$(date -r "$adblockscript" 2>/dev/null)"
	lastconfig="$(cat "$prefix/lastmod-config" 2>/dev/null)"
}


elog "Running as $me $@"

loadconfig

if [ -L $me -a "$cgimode" = "1" -a -e $me.weblink ]; then
 	if [ "$me" != "$(cat "$me.weblink")" ]; then
		# apparently called as cgi wrapper, but name doesn't match
    		elog "<br>"
		elog "weblink file exists in script folder but running script name does not match <br>"
		elog "script name: $me, weblink value: $(cat $me.weblink) <br>"
		pexit 20
	fi
fi


# if called via weblink, execute $webscript
if [ "$me" = "$weblink" ]; then
	for e in $(set | grep "^web.*=")
	do
		export "${e%=*}"
	done
	export adblockscript
	export binprefix
	export blacklist
	export blocklist
	export chain
	export config
	export dnsmasq_config
	export hostlink
	export listprefix
	export modehost
	export pixelbin
	export prefix
	export redirip
	export release
	export testhost
	export weblink
	export webscript
	export whitelist
	export FWBRIDGE
	export PIXEL_IP
	export LISTMODE
	export thisconfig
	export lastconfig
	if [ -x "$binprefix/$webscript" ]; then
		# use the script in this folder if it exists
		export webscript="$binprefix/$webscript"
	elif [ -x "$( which "$webscript" )" ]; then
		export webscript
	else
		echo "<html><head><title>Adblock Web Error</title></head><body>
			ERROR: Web Script $webscript not found or not executable!</body></html>"
		elog "ERROR: Web Script $webscript not found or not executable!"
		pexit 0  &> /dev/null
	fi
	elog "Executing $webscript QUERY_STRING="$QUERY_STRING""
	"$webscript"
	[ "$quietcgi" = "1" ] && exit 0 || pexit 0 &> /dev/null
fi

# display queue and disable cgi mode
[ "$cgimode" = "1" ] && flushlog

# exit if another instance is running
kill -0 $(cat $pidfile 2>/dev/null) &>/dev/null && {
	flushlog
	elog "Another instance found ($pidfile - $(cat "$pidfile")), exiting!"
	exit 1
}

echo $$ > $pidfile

# called via .fire autorun link - reload firewall rules and exit
if [ "$me" = "$fire" ]; then
	elog "Updating iptables"
	startserver
	[ "$quietfire" = "1" ] && exit 0 || pexit 0 &> /dev/null
fi

flushlog

# called via .shut autorun link - execute shutdown
if [ "$me" = "$shut" ]; then
	elog "System shutdown"
	shutdown
	pexit 0
fi

# write weblink
if [ "$weblink" != "" ] &&  [ -x "$binprefix/$webscript" -o -x "$( which "$webscript" )" ]; then
	if ln -sf "$me" "$weblink" ; then
		local lanport=$(nvram get http_lanport)
		[ "$lanport" = 80 -o "$lanport" = "" ] && lanport="" || lanport=":$lanport"
		elog "Creating web link $weblink"
		elog "Web interface should be available at http://$(nvram get lan_ipaddr)$lanport/user/${weblink##*/}"
		echo "$weblink" >  $weblink.weblink
		addtomatolink
	else
		elog "ERROR - could not create web link $weblink"
	fi
else
	elog "ERROR - Web Script $webscript not found or not executable!"
fi

echo "$@" | grep -q debug && debug=1

for p in $@
do
case "$p" in
	"clean")
		logvars
		elog "Processing '$p' option, remaining options ignored"
		cleanfiles
		pexit 0
		;;
	"fire")
		logvars
		elog "Processing '$p' option, remaining options ignored"
		fire
		pexit 0
		;;
	"stop")
		logvars
		elog "Processing '$p' option, remaining options ignored"
		stop
		cru d $cronid
		pexit 0
		;;
	"toggle")
		[ $currentmode != "OFF" ] && {
			logvars
			elog "Processing '$p' option, remaining options ignored"
			stop
			pexit 0
		}
		;;
	"cron")
		cru a $cronid "$schedule  $me update"
		;;
	"force")
		force="1"
		;;
	"restart")
		stop
		;;
	"update")
		update="1"
		;;
	"debug")
		;;
	*)
		elog "'$p' not understood! - no action taken"
		pexit 1
		;;
esac
done

logvars

[ $currentmode != "OFF" ] && elog "Blocklist active in $currentmode mode"

# rebuild blocklist if script, config, whitelist or blacklist has changed
[ "$thisconfig" != "$lastconfig" ] && {
	elog "Config or script has changed - rebuilding list"
	restartpix=1
	echo -n "" >  $blocklist
}

# remove existing list if not built for $LISTMODE or $redirip
[ -s $blocklist ] && {
	if ! head -n 1 $blocklist | grep -qm1 "MODE=$LISTMODE"; then
		elog "Existing blocklist is not $LISTMODE mode - removing"
		echo -n "" >  $blocklist
	elif ! head -n 1 $blocklist | grep -qm1 "IP=$redirip"; then
		elog "Existing blocklist is not for IP $redirip - removing"
		echo -n "" >  $blocklist
	fi
}

# completely skip update if script is less than $age2update hours old
now=$(date +%s)
listdate=$(date -r "$blocklist" +%s 2> /dev/null)
listage=$(( now - listdate ))

[ $listage -gt $(( age2update * 3600 )) -o "$force" = "1" -o "$update" = "1" -o ! -s "$blocklist" ] && {
	buildlist
} || {
	elog "List not old enough to update"
 	[ "$currentmode" = "$LISTMODE"  ] && {
		startserver
		pexit 0
	}
}

[ "$restartpix" = "1" ] && stopserver
startserver
writeconf
restartdns
echo "$thisconfig" > "$prefix/lastmod-config"

pexit 0

#
