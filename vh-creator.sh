#!/bin/bash

# --- --- --- PREAMBLE --- --- ---

YELLOW="\033[33m"
GREEN="\033[92m"
RED="\033[91m"
CYAN="\033[96m"
RESET="\033[0m"

cfg_path="config.cfg"

# match($1 = prefix) -> string: Matches a line with the prefix $prefix in $cfg_path and returns the succeeding string.
match () {
	echo $(grep -o "$1=\"[^\"]*\"" "$cfg_path" | sed -e "s/$1=\"//" -e "s/\"//")
}

# replace($1 = prefix, $2 = replace_with, $3 = target_file) -> void: Replaces the succeeding string in file $target_file after $prefix with $replace_with.
replace() {
	sed -i "s@\($1\s\s*\).*@\1$2@" "$3"
}

# replace_simple($1 = match, $2 = replace_with, $3 = target_file) -> void: Replaces any occurences of $match with $replace_with in file $target_file.
replace_simple() {
    sed -i "s/$1/$2/g" $3
}

zones_path=$(match zones_path)
nginx_path=$(match nginx_path)
html_path=$(match html_path)
sites_available_path=$nginx_path'/sites-available'
sites_enabled_path=$nginx_path'/sites-enabled'

server_name=$(match server_name)
db_name=$(match db_name)
db_reverse_lookup_name=$(match db_reverse_lookup_name)

dns_forward_lookup_path=$zones_path/$db_name
dns_reverse_lookup_path=$zones_path/$db_reverse_lookup_name

sample_nginx_config_path=$(match sample_nginx_config_path)
sample_index_path=$(match sample_index_path)

temp_path=$(match temp_path)
backup_path=$(match backup_path)

# clean(void) -> void: Cleans the temp directory. Immediately exits with code 1 when $temp_path is the root directory '/' or its children '/*' 
clean() {
	if [ $temp_path = "/" ]	|| [ $temp_path = "/*" ]; then
		echo "Risky temp path: '$temp_path'. Consider changing 'temp_path' in config file '$cfg_path'."
		exit 1
	else
		find $temp_path -mindepth 1 -delete
		touch $temp_path/.gitkeep
		# echo "Temp directory cleaned successfully."
	fi
}

# get_dns_self(void) -> string: Gets the reversed host portions of host's IP.
get_dns_self() {
	hostname=$(hostname -i | grep -o "[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*")
	host_1=$(echo $hostname | sed -e "s/[0-9]*\.[0-9]*\.//" -e "s/\([0-9]*\).[0-9]*/\1/")
	host_2=$(echo $hostname | sed -e "s/[0-9]*\.[0-9]*\.//" -e "s/[0-9]*.\([0-9]*\)/\1/")
	echo "$host_2.$host_1"
}

get_hostname() {
	echo $(hostname -i | grep -o "[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*")
}

# --- --- --- MAIN --- --- ---

# Clean the temp directory

echo
clean

# Receive inputs from user

echo -n ">> Enter server name (e.g. python.cpe36.net): "
read server_name
server_name=$(echo $server_name | tr -d ' ')

# Copy the template files to temp

temp_nginx_config_path="$temp_path/$server_name"
temp_index_path="$temp_path/index.html"

cp $sample_nginx_config_path $temp_nginx_config_path
cp $sample_index_path $temp_index_path

# Modify the template files

replace "root" "$html_path/$server_name;" $temp_nginx_config_path
replace "server_name" "$server_name;" $temp_nginx_config_path
replace_simple "\[server_name\]" "$server_name" $temp_index_path

# Copy the DNS forward & reverse lookup database files to temp

temp_dns_forward_path="$temp_path/$db_name"
temp_dns_reverse_path="$temp_path/$db_reverse_lookup_name"

cp $dns_forward_lookup_path $temp_dns_forward_path
cp $dns_reverse_lookup_path $temp_dns_reverse_path

# Modify the database files

line="$(get_dns_self)\tIN\tPTR\t$server_name.\t;"
echo -e $line >> $temp_dns_reverse_path

line="$server_name.\t\tIN\tA\t$(get_hostname)"
echo -e $line >> $temp_dns_forward_path

# Back up the DNS database files in case things go wrong

timestamped_backup_path="$backup_path/$(date +%s)"
mkdir $timestamped_backup_path

cp $dns_forward_lookup_path "$timestamped_backup_path/$db_name"
cp $dns_reverse_lookup_path "$timestamped_backup_path/$db_reverse_lookup_name"

# Dispatch the Nginx config files to nginx/sites-available and create symbolic links in sites-enabled

mv $temp_nginx_config_path "$sites_available_path/$server_name"
ln -s "$sites_available_path/$server_name" "$sites_enabled_path/$server_name" 2>/dev/null

# Create a new directory for the website and dispatch the index file to it

echo
printf $CYAN"Dispatching site configuration files..."$RESET"\n"
mkdir "$html_path/$server_name" 2>/dev/null
mv $temp_index_path "$html_path/$server_name"

# Check config & restart Nginx

printf $YELLOW"Checking Nginx config..."$RESET"\n"
echo

nginx -t
if [ $? -eq 0 ]; then
	echo
    	printf $GREEN"Nginx configuration check successful."$RESET"\n"
	echo "Restarting Nginx..."
else
	echo    	
	printf $RED"ERROR: erroneous Nginx configuration. Check $sites_available_path/$server_name for errors."$RESET"\n"
	echo "Process aborted."
	exit 1
fi

service nginx restart

# Dispatch the database files to bind/zones
# But first, check if the database files already contain the domain names.

echo

# Check forward lookup file

printf $CYAN"Dispatching DNS DB files..."$RESET"\n"
if grep -q $server_name $dns_forward_lookup_path; then
	printf "Definition for $server_name already exists in the forward lookup file.\n"
	echo "Aborting update (none needed.)"
else
	mv $temp_dns_forward_path $dns_forward_lookup_path
fi

# Check reverse lookup file

if grep -q $server_name $dns_reverse_lookup_path; then
	printf "Definition for $server_name already exists in the reverse lookup file.\n"
	echo "Aborting update (none needed.)"
else
	mv $temp_dns_reverse_path $dns_reverse_lookup_path
fi

# Check config & restart Named

printf $YELLOW"Checking Named config..."$RESET"\n"
echo

named-checkconf
if [ $? -eq 0 ]; then
	printf $GREEN"Named configuration check successful."$RESET"\n"
	echo "Restarting Named..."
else
	echo
	printf $RED"ERROR: erroneous Named configuration."$RESET"\n"
	echo "Check $dns_forward_lookup_path & $dns_reverse_lookup_path for errors."
	printf "To perform a rollback, type: "
	printf $YELLOW"mv $timestamped_backup_path/* $zones_path"$RESET"\n"
	echo "Process aborted."	
	exit 1
fi

service named restart

echo
printf $GREEN"Site created successfully, try:$RESET lynx $server_name""\n"
echo
echo "To revert the DNS configurations to an earlier state, type:"
printf $YELLOW"mv $timestamped_backup_path/* $zones_path"$RESET"\n"
echo

exit 0
