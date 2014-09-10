#!/bin/sh

## Modified from Clean, Lean and Mean Adblock v4.5 by haarp
##
## http://www.linksysinfo.org/index.php?threads/script-clean-lean-and-mean-adblocking.68464/
##
## Use at your own risk
##
## Options:
## 'force': force updating sources,
## 'stop': disable Adblock, 'toggle': quickly toggle Adblock on and off
## 'restart': restart Adblock (e.g. for config changes)
##
## TODO: 'clean', 'status' options
##
## Changes from haarp's 4.5:
## =========================
##
## 2013-11-30
## ----------
## 'cron' option - add to scheduler for updates
## 'update' option - require update check regardless of list age
## don't attempt list update if blocklist less than x hours old
## blocklist and config files moved out of executable folder
## $config file can override most path assumptions
## rebuild blocklist if config, whitelist, or blacklist has changed
## tweak rules to close connections faster
## tweak rules to support ssl aware pixelserv - ASSUMES v32 or greater
## create firewall autorun link to survive firewall reset
## blank lines and whitespace stripped from whitelist - reduce odds of over matching
## minor speed improvement with config file based whitelist entries
##
## 2013-12-01
## ----------
## Fix link to firewall autorun script - was being overwritten.
##
## 2013-12-04
## ----------
## Find true script folder when called via autorun link and config is located in $binprefix
## Add back haarp's "cd $prefix" for compatibility
##
## 2013-12-11
## ----------
## process config based whitelist entries correctly when no whitelist file exists (fix jerrm regression)
## orphaned source files in $prefix no longer appended to blocklist (fix long standing issue)
## strip carriage returns from whitelist/blacklist files (new)
## strip blocklist of any lines with invalid characters (new)
## firewall rules moved to separate chain for easier/more reliable cleaning (new)
## allow multiple command line parameters (new)
## 'fire' option added - updates firewall rules and exit (new)
## 'clean' option added - cleans script generated files (new)
## 'debug' option added - very rudimentary, simply logs environment (new)
##
## search common folders for config file (new)
##   1: Check for the file "config" in script folder, if found default to
##      "legacy" mode for haarp compatibility, assuming all files are in
##      script folder.
##
##   2: If "config" is not found, check for the files listed in $configlist.
##      The first match found is used as the config file. The config file folder
##	is used for $prefix if it is already named "adblock", otherwise an
##	"adblock" subfolder is created as the $prefix folder.
##
##	$configlist looks for the config file under the script folder, /jffs,
##	/opt, /cifs1, /cifs2, /etc, and /tmp.  It also checks if the file exists
##	in an etc or adblock subfolder for each of the above.
##
##      $prefix can be redefined in the config file to point elsewhere.
##
## set defaults for following config variables in main script (new):
##   $BRIDGE, $PIXEL_IP, $PIXEL_OPTS, $RAMLIST, $PIXEL_IP, $PIXEL_OPTS, $RAMLIST, $CONF
##   all can be redefined in config file.
##
## default $BRIDGE to nvram lan_ifname instead of br0, config file overrides (new)
##
## add $FWRULES config variable to adjust rule generation - see below discussion. (new)
##   FWRULES=STRICT : drop connections from unknown interfaces (DEFAULT)
##   FWRULES=LOOSE  : allow all traffic from unknown interfaces
##		      (mimics behavior of prior releases)
##   FWRULES=NONE   : do not generate any firewall rules
##
## add $FWBRIDGE config variable for basic vlan support, defaults to 'br+' value (new)
##
##   example:	set FWBRIDGE="br+" for most instances when internal vlans exist,
##		set to "br0" to only allow a single vlan access to pixelserv,
##		use list of interfaces "br0 br2 tun+" for more unique needs,
##
##  ** NOTE **	Original script intent was apparently to only allow pixelserv
##		requests to the $redirip address. The old rules never worked
##		correctly in VPN or VLAN environments.
##
##		Prior rules always assumed a single vlan. Pixelserv usually
##		worked when accessed from the additional vlans because the
##		script rules allowed all traffic from unknown interfaces.
##
##		The new rule default (FWRULES=STRICT) now drops all packets
##		to $redirip from unknown interfaces. "Known" interfaces are
##		defined with $FWBRIDGE.
##
##		Properly setting FWBRIDGE is the recommended action, but old
##		behavior can be restored by setting FWRULES=LOOSE in config
##		file.
##
##		To disable all rule generation set FWRULES=NONE.
##
##		Rules should be functional for default Tomato VLAN behavior
##		in most instances.
##
##		Only a basic/best effort attempt can be made to handle VPN
##		traffic. Tomato auto VPN rules do not properly clean themselves
##		and insert an ACCEPT all at the head of the input chain.
##		Re-running the adblock script after change in VPN connection
##		status should properly re-apply the rules, but without knowing
##		all the possible Tomato permutations, no guarantees can be
##		made. If "up" and "down" scripts are defined for VPN
##		connections, calling the adblock firewall autorun link or
##		using the new "fire" option from the up/down scripts should
##		properly reapply the rules.
##
##		Consider setting FWRULES=NONE and customizing rules manually
##		if using VPN or anything else unusual.
##
## 2013-12-22
## ----------
## use a more unique virtual interface ID, less chance of conflicts (new)
## clean up pixelserv and virtual IP if PIXEL_IP=0 (new / bug fix)
## be a little smarter about firewall rules if PIXEL_IP=0 (new)
## be a little smarter about stopping pixelserv (new)
## be a little smarter about dnsmasq restarts (new)
## allow blacklist only without downloaded source lists - set SOURCES="" in config (new)
## allow ping to virtual IP from $FWBRIDGE interfaces (new)
## check for zero byte download files - avoid overwriting prior download on drives with enough space (new)
## blocklist temp file moved to /tmp to reduce writes to jffs/usb for routers with sufficient free space (new)
## $listtmp config variable added to override default blocklist temp file location (new)
## add header to blocklist with $LISTMODE and $redirip (new)
## add LISTMODE config options for blocklist generation - see below (new for this script - from srouquette's mod)
##
## LISTMODE options:
##
##   Haarp uses dnsmasq's "address" directive to assign addresses for list dns
##   names. The address directive does not match just a single host, but will
##   return the $redirip for ANY host ending in the the given name.
##
##   In other words, if only "bar.com" is listed in the blocklist, then
##   www.bar.com, foo.bar.com, www.foo.bar.com, etc, are also blocked.
##
##   Using doubleclick.net as an example, "doubleclick.net" is the domain for
##   104 entries in a large test list. Since "doubleclick.net" itself is
##   included in the list without any additional host/sub-domain qualifier, the
##   extra 103 entries provide no functionality and only eat up memory.
##
##   Srouquettes's all-u-need mod removed unneeded subdomains/hosts, but
##   the option got dropped along the way in haarp's rewrite.
##
##   This version puts back srouquettes subdomain removal with some speed
##   improvements (but still slower than wished). With haarp's method and a
##   large test list, blocklist building takes 95 seconds and uses 52MB
##   memory when loaded by dnsmasq. Using the subdomain removal code,
##   list building takes 360 seconds, but only uses 16MB memory once loaded.
##   For comparison, Srouquette's removal takes 620 seconds for the same list.
##
##   The relative speeds and memory usage vary based on the domain/hosts mix
##   of the lists used, but the basic ratios appear to hold across several
##   test cases.
##
##   Also restored from srouquette's mod is HOST mode. Features fastest list
##   building, but less aggressive matching since only the listed hosts are
##   blocked.  Some may prefer this more precise method, or find it a good
##   balance between speed, memory usage and functionality.
##
##   OPTIMIZE (default - slower build speed, best memory useage)
##   -----------------------------------------------------------
##   Removes unneeded subdomains/hosts from the blocklist.  Should be
##   functionally equivalent to legacy, but with less memory usage. Trade off
##   is list build speed.
##
##   LEGACY (faster, but at the cost of memory)
##   ------------------------------------------
##   This is the mode used by haarp's version of the script, it can result in
##   a list that is two, three, or more times larger than needed.
##
##   HOST (fastest build, more specific matching, good memory usage)
##   ---------------------------------------------------------------
##   Does not use the "address" directive, but instead creates a hosts file for
##   the blocklist entries. List build speed is better than LEGACY, memory
##   usage is is closer to the OPTIMIZE low end than the LEGACY high end. Least
##   risk of false positives - only matches hosts explicitly listed in the
##   blocklist.
##
##   Another advantage is HOST mode does not require a full dnsmasq restart
##   when enabling, disabling or updating the blocklist.
##
## 2014-01-05
## ----------
## make sure file permissions allow dnsmasq to read the file after dropping root
##   Only an issue with HOST mode because the hosts files are read after dnsmasq
##   drops root privileges. If adblock is called from wanup with a ppp wan
##   connection the inherited default mask only allowed root access the file.
## add shutdown autorun for better handling of no-reboot shutdown/init sequences
## re-establish $redirip if necessary
## honor gui log settings
## don't write dnsmasq files if blocklist is missing - there was an un-reproduced bug report
## add some more debug output
##

#########################################################
#							#
# Static values - these cannot / should not be changed  #
# in the config file.					#
#							#
#########################################################

umask 0022

alias elog='logger -t ADBLOCK -s'
alias iptables='/usr/sbin/iptables'
alias nslookup='/usr/bin/nslookup'
alias ls='/bin/ls'
alias df='/bin/df'

pidfile=/var/run/adblock.pid

# router memory
ram=$(awk '/^MemTotal/ {print int($2/1024)}' < /proc/meminfo)

# this script
me="$(cd $(dirname "$0") && pwd)/${0##*/}"

# path to script -  was script called via an autorun link?
[ ${me##*"."} = "fire" -o  ${me##*"."} = "wanup" -o  ${me##*"."} = "shut" ] && {
	# yes - find true script folder
 	s="$( ls -l "$me" )"; s="${s##*" -> "}"
	binprefix="$(cd "$(dirname "$me")" && cd "$(dirname "$s")" && pwd)"
	islink=1
} || {
	# no -  use folder of $me
	binprefix="$(dirname "$me")"
	islink=0
}

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

# list mode
LISTMODE="OPTIMIZE"

# default to using primary lan interface
BRIDGE="$(nvram get lan_ifname)"

# default to strict firewall rules
FWRULES=STRICT

# default interface(s) for firewall rules
# supports multiple interfaces as well, ie: "br0 br1 br3"
FWBRIDGE="br+"

# set haarp config defaults - config file overrides
# 0: disable pixelserv, 1-254: last octet of IP to run pixelserv on
PIXEL_IP=254

# additional options for pixelserv
PIXEL_OPTS=""

# 1: keep blocklist in RAM (e.g. for small JFFS)
RAMLIST=0

# dnsmasq custom config (must be sourced by dnsmasq!) confused? then leave this be!
CONF=/etc/dnsmasq.custom

#whitelist and blacklist contents
BLACKLIST=""
WHITELIST=""

#########################################################
# End of default values					#
#########################################################

pexit() {
	elog "Exiting $me $@"
	rm -f "$pidfile" &>/dev/null
	exit $@
}

dlog() {
	[ "$debug" = "1" ] && elog "$@"
}

logvars() {
	[ "$debug" != "1" ] && return
	elog "Initialized Environment:"
	set | ( while read line; do elog "    $line"; done )
	elog "Mounted Drives"
	mount | ( while read line; do elog "    $line"; done )
	elog "Free Space"
	df -h | ( while read line; do elog "    $line"; done )
	elog "prefix folder - $prefix"
	ls -lh $prefix | ( while read line; do elog "    $line"; done )
	elog "listprefix folder - $listprefix"
	ls -lh $listprefix | ( while read line; do elog "    $line"; done )
	elog "listtmp folder - $listtmp"
	ls -lh $listtmp | ( while read line; do elog "    $line"; done )
}

startserver() {
	if [ "$PIXEL_IP" != "0" ]; then
		if ! ifconfig | grep -q $BRIDGE:$vif; then
			elog "Setting up $redirip on $BRIDGE:$vif"
			ifconfig $BRIDGE:$vif $redirip up
		fi
		if ps | grep -v grep | grep -q "$pixelbin $redirip"; then
			elog "pixelserv already running, skipping"
		else
			elog "Setting up pixelserv on $redirip"
			"$pixelbin" $redirip $PIXEL_OPTS
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
	killall pixelserv &>/dev/null
	ifconfig $BRIDGE:$vif down &>/dev/null
}


rmfiles() {
	rm -f "$fire" &>/dev/null
	rm -f "$shut" &>/dev/null
	rm -f "$CONF" &>/dev/null
	rm -f "$hostlink" &>/dev/null
	rm -f "$tmpstatus" &>/dev/null
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
	[ $LISTMODE = "HOST" ] && {
		[ $currentmode = "HOST" -o $currentmode = "OFF" ] && {
			elog "Loading hosts file for dnsmasq"
			kill -HUP $( pidof dnsmasq )
			return
		}
	}
	elog "Restarting dnsmasq"
	service dnsmasq restart
}

writeconf() {
	[ ! -f $blocklist ] && {
		elog "Blocklist Missing - REMOVING DNSMASQ FILES / ADBLOCK MAY BE DISABLED!"
		rm -f "$CONF" &>/dev/null
		rm -f "$hostlink" &>/dev/null
		return
	}

	[ $LISTMODE = "HOST" ] && {
		rm -f "$CONF" &>/dev/null
		ln -sf "$blocklist" "$hostlink"
	} || {
		rm -f "$hostlink" &>/dev/null
		echo "conf-file=$blocklist" > "$CONF"
	}
}

cleanfiles() {
	cru d $cronid
	stop
	elog "Cleaning files"
	rm -f $prefix/lastmod-* &> /dev/null
	rm -f $prefix/source-* &> /dev/null
	rm -f $tmpstatus &> /dev/null
	rm -f $blocklist  &> /dev/null
	elog "The following files remain for manual removal:"
	ls -1Ad $me $config $listprefix/* $prefix/* 2>/dev/null| sort -u | ( while read line; do elog "    $line"; done )
}

shutdown() {
	rmfiles
	stopserver
}

#########################################################
# - firewall rules moved to separate proc to allow	#
#   autorun link					#
# - these rules assume ssl aware pixelserv v32 or later	#
# - use reject to close connections more quickly	#
# - support vlan configs (preliminary)			#
#########################################################
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

	(
		if wget $1 -O -; then
			echo 0 >>"$tmpstatus"
		else
			elog "Failed: $1"
			echo 1 >>"$tmpstatus"
		fi
	) | tr -d "\r" | sed -e '/^[[:alnum:]:]/!d' | awk '{print $2}' | sed -e '/^localhost$/d' > "$sourcefile.$$.tmp"

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

	#########################################################
	# build list of source files to load			#
	#							#
	# previously entire $listprefix folder was processed 	#
	# which could contain orphaned and unwanted files	#
	#########################################################
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
		if [ ! -f "$blocklist" ]; then
			elog "Blocklist does not exist"
			confgen
		elif [ "$LISTMODE" != "$currentmode" -a "$currentmode" != "OFF" ]; then
			elog "Mode changed"
			confgen
		elif [ "$LISTMODE" = "$currentmode" ]; then
			elog "Mode unchanged"
			# no changes to list and already running in current mode
			writeconf # re-write conf or link if needed
			pexit 2   # but nothing else to do, so exit
		fi
	else
		elog "Download failed"
		if [ -f "$blocklist" -a ! -f "$CONF" ]; then #needlink
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

  	trap 'elog "Signal received, cancelling"; rm -f "$tmpwhitelist" "$tmpblocklist" "$blocklist" &>/dev/null; pexit 140' SIGQUIT SIGINT SIGTERM SIGHUP

	# only allow valid hostname characters
	echo "[^a-zA-Z0-9._-]+"  > "$tmpwhitelist"

	(
		if [ -f "$whitelist" ]; then
			# strip blank lines, spaces and carriage returns from whitelist
			cat "$whitelist" | sed 's/[ |\t|\r]*//g; /^$/d'
		fi

		# add config file whitelist entries to temp file
		for w in $WHITELIST; do
			echo $w
		done
	)  >> "$tmpwhitelist"

	[ -f "$blacklist" ] && {
		# strip blank lines, spaces and carriage returns from blacklist
		cat "$blacklist" | sed 's/[ |\t|\r]*//g; /^$/d' > "$tmpblocklist"
	}
	for b in $BLACKLIST; do
		echo "$b" >> "$tmpblocklist"
	done

	# add hosts to test if adblock is loaded
	echo $testhost >> "$tmpblocklist"

	echo $LISTMODE.$modehost >> "$tmpblocklist"

	# use sourcefiles list (and not all files in folder which could have old/unwanted files)
	[ -n "$sourcelist" ] && cat $sourcelist | grep -Ev -f "$tmpwhitelist" >> "$tmpblocklist"

	rm -f "$tmpwhitelist" &>/dev/null

	# add header to blocklist, used to determine what mode the list was built for
	# do not alter format without adjusting the grep regex that tests the mode/ip
	echo "# adblock blocklist, MODE=$LISTMODE, IP=$redirip, generated $(date)" > $blocklist

	case $LISTMODE in
		HOST)
			sort -u  "$tmpblocklist" |
			sed -e "s:^:$redirip :" >> "$blocklist"
		;;
		OPTIMIZE)
			sed -e :a -e 's/\([^\.]*\)\.\([^\.]*\)/\2#\1/;ta'  "$tmpblocklist" | sort |
  			awk -F '#' 'BEGIN{d = "%"} { if(index($0"#",d)!=1&&NF!=0){d=$0"#";print $0;} }' |
			sed -e :a -e 's/\([^#]*\)#\([^#]*\)/\2\.\1/;ta' -e "s/\(.*\)/address=\/\1\/$redirip/" >> "$blocklist"
		;;
		LEGACY)
			sort -u  "$tmpblocklist" |
			sed  -e '/^$/d'  -e  "s/\(.*\)/address=\/\1\/$redirip/" >> "$blocklist"
		;;
	esac
	rm -f "$tmpblocklist" &>/dev/null

  	trap -  SIGQUIT SIGINT SIGTERM SIGHUP

	elog "Blocklist generated - $(( $(date +%s) - cg1 )) seconds"
	elog "$(wc -l < "$blocklist") unique hosts to block"
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

	#########################################################
	# redirip can be explicitly set in the config file,	#
	# but make sure it is valid as no checks are done	#
	#							#
	# PIXEL_IP still needs to be set to non-zero for the	#
	# pixelserv to be started				#
	#########################################################
	[ "$redirip" = "" ] && redirip=$(ifconfig $BRIDGE | awk '/inet addr/{print $3}' | awk -F":" '{print $2}' | sed -e "s/255/$PIXEL_IP/")

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

	if [ "$PIXEL_IP" = "0" ]; then
		redirip="0.0.0.0"
	else
		[ -x "$pixelbin" ] || {
			elog "$pixelbin not found/executable!"
			pexit 10
		}
	fi

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
	thisconfig="$thisconfig|$me:$(date -r "$me" 2>/dev/null)"
	lastconfig="$(cat "$prefix/lastmod-config" 2>/dev/null)"
}

elog "Running as $me $@"

kill -0 $(cat $pidfile 2>/dev/null) &>/dev/null && {
	elog "Another instance found ($pidfile), exiting!"
	exit 1
}

echo $$ > $pidfile

loadconfig

#########################################################
# if being called via the firewall autorun link	reload	#
# firewall rules and exit				#
#########################################################
if [ "$me" = "$fire" -o  "$me" = "$wanup" ]; then
	elog Updating iptables
	startserver
	pexit 0
fi

if [ "$me" = "$shut" ]; then
	elog System shutdown
	shutdown
	pexit 0
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
	rm -f $blocklist &>/dev/null
}

# remove existing list if not built for $LISTMODE or $redirip
[ -f $blocklist ] && {
	if ! head -n 1 $blocklist | grep -qm1 "MODE=$LISTMODE"; then
		elog "Existing blocklist is not $LISTMODE mode - removing"
		rm -f $blocklist &>/dev/null
	elif ! head -n 1 $blocklist | grep -qm1 "IP=$redirip"; then
		elog "Existing blocklist is not for IP $redirip - removing"
		rm -f $blocklist &>/dev/null
	fi
}

# completely skip update if script is less than $age2update hours old
now=$(date +%s)
listdate=$(date -r "$blocklist" +%s 2> /dev/null)
listage=$(( now - listdate ))

[ $listage -gt $(( age2update * 3600 )) -o "$force" = "1" -o "$update" = "1" ] && {
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