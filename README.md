AdBlock Web Gui
==============

AdBlock Web Gui for Jerrm script

AdBlock Web GUI by Almaz
Version: 1.3
Using Tomato firmware just put all the files in /var/wwwext/

##############################################################################
adblockpath="/var/wwwext/adblock.sh"  	# location of adblock.sh by Jerrm
pixelservip="192.168.1.254"				# Pixelserv IP address		
scriptname="ads.sh"						# this script name
dnsmasqlog="/tmp/var/log/messages*"		# dnsmasq log location, by default it's using syslog
tmpfolder="/tmp"						# location of your temp folder
dnsmasq_external_log="n"				# If you are using external dnsmasq log then enter "y" otherwise "n" for default syslog
##############################################################################