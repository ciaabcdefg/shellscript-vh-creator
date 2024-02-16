#!/bin/bash

# --- --- --- PREAMBLE --- --- ---

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

sample_nginx_config_path=$(match sample_nginx_config_path)
sample_index_path=$(match sample_index_path)

temp_path=$(match temp_path)

# clean(void) -> void: Cleans the temp directory. Immediately exits with code 1 when $temp_path is the root directory '/' or its children '/*' 
clean() {
	if [ $temp_path = "/" ]	|| [ $temp_path = "/*" ]; then
		echo "Risky temp path: '$temp_path'. Consider changing 'temp_path' in config file '$cfg_path'."
		exit 1
	else
		# find $temp_path -mindepth 1 -delete	
		echo "Temp directory cleaned successfully."
	fi
}

# --- --- --- MAIN --- --- ---

# Clean the temp directory

echo
clean

# Receive inputs from user

echo -n ">> Enter server name (e.g. python.cpe36.net): "
read server_name
server_name=$(echo $server_name | tr -d ' ')

echo $server_name

# Copy the Nginx template file to temp

temp_nginx_config_path="$temp_path/temp_nginx_config"
temp_index_path="$temp_path/temp_index.html"

cp $sample_nginx_config_path $temp_nginx_config_path
cp $sample_index_path $temp_index_path

# Replace the temp files definitions with new ones

replace "root" "$html_path/$server_name;" $temp_nginx_config_path
replace "server_name" "$server_name;" $temp_nginx_config_path
replace_simple "\[server_name\]" "$server_name" $temp_index_path



