#!/bin/sh
#
# based on the migration script in the Ubuntu package
#
# Global variables
# ServicePath  - location of systemd (either /etc/systemd, /usr/lib/systemd, or /lib)
# UserConfig    - where we found the user's current configuration
# OverrideDir   - where we will be putting the new configuration information

# Define the PMS core default variables.  Needed to detect changes from defaults
PLEX_MEDIA_SERVER_HOME="/usr/lib/plexmediaserver"

# Initialize variables and process flags
NewAppSupport=""; NewTmp=""; NewUser=""; NewGroup=""

# Set the changed flags
ChangedApp=0; ChangedTmp=0; ChangedUser=0; ChangedGroup=0;

# True (1) if the service override file is needed (User or Group changed)
NeedOverride=0; HaveOverride=0;

# (User) Configuration found flag and file name
HaveConfig=0; ConfigPath="/etc/sysconfig/PlexMediaServerConfig"

# Systemd Override path  (This is the new service override location for systemd)
NeedOverride=0; OverrideDir="/etc/systemd/system/plexmediaserver.service.d"

# Temp file to use 
Temp=`mktemp` 

# Set DebugOn=1 to enable console log (debug)
DebugOn=0

#=================================== DEBUG ====================================

Debug() {
  if [ $DebugOn -eq 1 ]; then

   echo MigratePlexServerConfig:  $1 $2 $3 $4 $5 $6 $7 $8 $9

  fi
}

#==============================================================================
# Utility Function:  IsNumber ()
# Return 1 if an integer number, 0 otherwise
IsNumber() {

  Regex='^[0-9]+$'
  if [[ "$1" =~ $Regex ]] ; then
     return 1
  fi
  return 0
}

#==============================================================================
# UpdateConfig ( ConfigFile, PMS-Variable, Var-with-Value )
#
# Removes the specified variable (if present) from the ConfigFile, appends 
# the new value and copies back to the original location (atomic) 
#
# Use this function to update an existing or write to a new config file

UpdateConfig() {

  Temp="`mktemp`"

  if [ -r "$1" ]; then
   grep -v $2 "$1"  > $Temp
  fi

  # Watch for numerical values
  IsNumber "{!2}"
  if [ $? -eq 1 ]; then
    echo ${2}=${!2} >> "$Temp"
    Debug Updating Config: ${2}=${!2}
  else
    echo ${2}=\"${!2}\" >> "$Temp"
    Debug  Updating Config: ${2}=\"${!2}\"
  fi

  cp -f "$Temp" "$1"
  chmod +x "$1"
  Debug rm -f "$Temp"
}



# ================== Main Routine:  MigratePlexServerConfig ===================

# Start with lowest priority variables and work to highest priortiy 
# User-> Service-> Override


# Step 1 - USER:    Locate, if possible, old user configuration file


 HaveConfig=0

 # Starting with the new PlexMediaServerConfig, look for user config files
 if [ -r "$ConfigPath" ]; then
  HaveConfig=1
  UserConfig="$ConfigPath"

 elif [ -r /etc/default/plexmediaserver ]; then
  HaveConfig=1
  UserConfig=/etc/default/plexmediaserver

 elif [ -r /etc/defaults/plexmediaserver ]; then
  HaveConfig=1
  UserConfig=/etc/defaults/plexmediaserver

 elif [ -r /etc/defaults/PlexMediaServer ]; then
  HaveConfig=1
  UserConfig=/etc/defaults/PlexMediaServer

 elif [ -r /etc/sysconfig/PlexMediaServer ]; then
  HaveConfig=1
  UserConfig=/etc/sysconfig/PlexMediaServer

 elif [ -r /etc/sysconfig/plexmediaserver ]; then
  HaveConfig=1
  UserConfig=/etc/sysconfig/plexmediaserver
 fi

 # Convert to usable form
 if [ $HaveConfig -eq 1 ]; then

  Debug "Found User Config at" $UserConfig

  # convert all 'export ' to shell variable assignments as we copy
  sed -e 's/^export //' < "$UserConfig" > $Temp

  # We are done with the user file, move it out of the way (abandon in place) if on systemd based systems
  if [ -f /proc/1/comm ] && [ "`cat /proc/1/comm`" = "systemd" ]; then
   mv -f $UserConfig ${UserConfig}.prev
  fi

  # Pull in the user config
  chmod +x "$Temp"

  . "$Temp"

  # Copy over ONLY what is important
  if [ $PLEX_MEDIA_SERVER_USER != plex ]; then
    ChangedUser=1
    ChangedGroup=1
    NewUser=$PLEX_MEDIA_SERVER_USER
    NewGroup=$PLEX_MEDIA_SERVER_USER
    if [ "$PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR" = "" ]; then
      PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR=`eval echo ~$PLEX_MEDIA_SERVER_USER`
      PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR="$PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR/Library/Application Support"
    fi 
  elif [ "$PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR" = "" ]; then
      PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR="/var/lib/plexmediaserver/Library/Application Support"
  fi

  if [ "$PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR" != "/var/lib/plexmediaserver/Library/Application Support" ]; then
    ChangedApp=1;
    NewAppSupport="$PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR"
    Debug User changed AppSupport to $NewAppSupport
  fi

  if [ $PLEX_MEDIA_SERVER_TMPDIR != "/tmp" ]; then
    ChangedTmp=1
    NewTmp="$PLEX_MEDIA_SERVER_TMPDIR"
    Debug User changed TMPDIR to $NewTmp
  fi
 else
   # no configuration to migrate
   exit 0
 fi

# Step 2 - SYSTEM - Get the base variables from the as-distributed service file (modified ?)

 # Find 'plexmediaserver.service'
 if [ -r /lib/systemd/system/plexmediaserver.service ]; then
  ServicePath="/lib/systemd/system/plexmediaserver.service"
 fi

 Debug Service Path  "$ServicePath"

 if [ "$ServicePath" = "" ]; then
  echo  ERROR:  NO SERVICE FILE
  exit 1
 fi

 # Get the Environment variables from the existing service file and convert
 # (User could have modified it)

 # Pick up Application Support Dir, Temp, User, and Group

 AppSupport="`awk -F'=' '/PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR=/ {gsub(/"/,"");print $3}' $ServicePath`"
 Debug Service file APP_SUPPORT = $AppSupport

 # Pick up NewTmp
 NewTmp="`awk -F'=' '/PLEX_MEDIA_SERVER_TMPDIR/ {gsub(/"/,"");print $3}' $ServicePath`"
 Debug Service file TMPDIR = $NewTmp

 # Find User
 User="`awk -F'=' '/User/ {gsub(/"/,"");print $2}' $ServicePath`"
 if [ $User = "plex" ]; then
   if [ ! -z $NewUser ]; then
     User=$NewUser
   else
     User=$User
   fi
 fi
 Debug Service file User = $User

 # Find Group
 Group="`awk -F'=' '/Group/ {gsub(/"/,"");print $2}' $ServicePath`"
 if [ $Group = "plex" ]; then
   if [ ! -z $NewGroup ]; then
     Group=$NewGroup
   else
     Group=$Group
   fi
 fi

 Debug Service File Group = $Group


# Step 3 - OVERRIDE -  Get the service overrides (if they exist) and append (stack on top)

# Find the Service Override file

 ServiceOverride="/etc/systemd/system/plexmediaserver.service.d/override.conf"
 OverrideDir="`dirname $ServiceOverride`"

 Override="${ServiceOverride}"

 # We are all done with Temp as well
 rm -f "$Temp"

# Step 5 - Detect and tag changes from standard 
 Debug Step 5
 if [ "$PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR" != "/var/lib/plexmediaserver/Library/Application Support" ]; then
  ChangedApp=1
  NeedOverride=1
  Debug PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR changed to \"$NewAppSupport\"
 fi

 if [ "$NewTmp" != "/tmp" ]; then
  ChangedTmp=1
  Debug PLEX_MEDIA_SERVER_TMPDIR changed to \"$NewTmp\"
 fi

# Detect User/Group change from service file, override or user config. Convert to Override
 if [ "$User" != "plex" ]; then
  NeedOverride=1
  ChangedUser=1
  Debug Detected Username service override, User=\"$User\"
 fi

 if [ "$Group" != "plex" ]; then
  NeedOverride=1
  ChangedGroup=1
  Debug Detected Group service override,  Group=\"$Group\"
 fi


# Step 6 - Create systemd override if needed
 if [ $NeedOverride -eq 1 ]; then

  Debug ====== Need Override file.  Creating "${OverrideDir}"/override.conf ======

  # Create override dir if does not exist
  mkdir -p "$OverrideDir"

  # Setup the new name 
  Override="${OverrideDir}"/override.conf

  # Move the old override if it exists
  if [ -f "$Override" ]; then
    mv -f "$Override" "${Override}.prev"
  fi

  # Create the empty override.conf
  cat <<EOT >"$Override"
#
# Plex Media Server - Systemd service override file
#
# All entries must be systemd compliant (Environrment="var=absolute_value")
#

[Service]

# If you wish to change Plex's Username or Group, uncomment the field(s) below and
# change to the correct values

#User=new_plex_username
#Group=new_plex_group

EOT


  # Add Application Support Dir to override if changed
  if [ $ChangedApp -eq 1 ]; then
    Debug Override PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR= ${NewAppSupport}
    echo "Environment=\"PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR=${NewAppSupport}\"" >> "$Override"
  fi

  # Add NewTmp if changed.  Also issue notice
  if [ $ChangedTmp -eq 1 ]; then

    # Add User and Group to the Override file if changed
    echo " " >> $Override
    echo "# Your PLEX_MEDIA_SERVER_NewTmp definition has been migrated forward for you. " >> $Override
    echo "# The prefered method of changing it is through the Plex/Web GUI Server settings for the Transcoer" >> $Override
    echo " " >>$Override
    echo "Environment=\"PLEX_MEDIA_SERVER_NewTmp=${NewTmp}\"" >> $Override
    Debug Override PLEX_MEDIA_SERVER_NewTmp= \"$NewTmp\"

  fi

  # Override User if changed
  if [ $ChangedUser -eq 1 ]; then
    Debug Override   User= "$User"
    echo "User=$User" >> $Override
  fi

  if [ $ChangedGroup -eq 1 ]; then
    Debug Override   Group= "$Group"
    echo "Group=$Group" >> $Override
  fi
 else
  rm $Override
 fi
 

 # Cleanup 
 Debug rm -f $Temp

systemctl daemon-reload

# Reload systemctl config
systemctl -q disable plexmediaserver
systemctl -q enable plexmediaserver
