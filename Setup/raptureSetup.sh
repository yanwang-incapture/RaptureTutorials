#!/bin/bash
HOST="http://etn.incapture.net:8080"
REFLEX_RUNNER_LATEST_HOST="https://github.com"
REFLEX_RUNNER_LATEST="$REFLEX_RUNNER_LATEST_HOST/RapturePlatform/Rapture/releases/latest"

function validate_curl_response {
  local curl_exit_code=$1
  local http_status_code=$2
  local error_message=$3

  if [[ $curl_exit_code -ne 0 || $http_status_code -ne 200 ]] ; then
    echo $error_message
    echo "Curl Exit Code: $curl_exit_code     HTTP Status Code: $http_status_code"
    exit 1
  fi
}

function prompt_yes_no {
  local prompt_message="$1 [Y/n] "
  local return_val

  while true; do
    read -p "$prompt_message" response
    if [ -z "$response" ]; then
      response="Y"
    fi

    case "$response" in
      Y*|y*) return_val=true
             break
        ;;
      N*|n*) return_val=false
             break
        ;;
    esac
  done

  echo $return_val
}

function get_download_link {
  local curl_results=$( curl -qLSsw '\n%{http_code}' $REFLEX_RUNNER_LATEST )
  validate_curl_response $? $(echo "$curl_results" | tail -n1) "There was a problem getting the link to the latest version of ReflexRunner at $REFLEX_RUNNER_LATEST."
  local page_html=$(echo "$curl_results" | sed \$d) #strip http status

  local pattern="href=\"(.*ReflexRunner.*\.zip)\""
  local use_next_zip=false
  while read line; do
    if $use_next_zip && [[ $line =~ $pattern ]]; then
      download_link="${BASH_REMATCH[1]}"
      break
    elif [[ $line =~ release-downloads ]]; then
      use_next_zip=true
    fi
  done <<< "$page_html"

  echo "$REFLEX_RUNNER_LATEST_HOST$download_link"
}

function find_in_filesystem {
  local search_string=$1
  local validation_string=$2
  local search_path=$3
  local return_val

  # If we were given a directory to look in, look there first
  if [ -n "$search_path" ]; then
    return_val=$(find $search_path -name $search_string 2>/dev/null |grep -m 1 $validation_string)
  fi

  # Then try standard locations
  if [ -z "$return_val" ]; then
    # It'll probably be within RaptureTutorials, but where is that? We're probably inside of it.
    local cur_dir=$(pwd)
    local pattern="(.*RaptureTutorials).*"
    if [[ $cur_dir =~ $pattern ]]; then
      search_path="${BASH_REMATCH[1]}"
    fi

    if [ -n "$search_path" ]; then
      return_val=$(find $search_path -name $search_string 2>/dev/null |grep -m 1 $validation_string)
    fi
  fi

  # If we couldn't find it in RaptureTutorials, search everywhere.
  if [ -z "$return_val" ]; then
    return_val=$(find / -name $search_string 2>/dev/null |grep -m 1 $validation_string)
  fi

  echo $return_val
}

set_up_reflex_runner=false
reflex_runner_is_in_path=false
reflex_runner_path=$(which ReflexRunner)
if [ -z "$reflex_runner_path" ]; then
  set_up_reflex_runner=$(prompt_yes_no "Are you interested in setting up ReflexRunner?")
else
  reflex_runner_is_in_path=true
fi

if $set_up_reflex_runner; then
  already_downloaded=$(prompt_yes_no "Have you already downloaded ReflexRunner?")

  if $already_downloaded; then
    echo "Looking for ReflexRunner in your filesystem. To avoid this search in the future, add ReflexRunner to your PATH."
    reflex_runner_path=$(find_in_filesystem ReflexRunner bin/ReflexRunner)
    if [ -z "$reflex_runner_path" ]; then
      echo "ReflexRunner not found in your filesystem."
    else
      echo "Found ReflexRunner at $reflex_runner_path."
    fi
  fi
fi

if $set_up_reflex_runner && [ -z "$reflex_runner_path" ]; then
  do_download=$(prompt_yes_no "Would you like to download ReflexRunner?")

  if $do_download; then
    default_reflex_runner_path=$(pwd)
    while true; do
      read -p "Enter the directory where you would like to save it, or 'skip' to cancel. [$default_reflex_runner_path] " directory
      if [ -z "$directory" ]; then
        directory=$default_reflex_runner_path
        break
      elif [ "$directory" = "skip" ]; then
        do_download=false
        break
      elif [ "$directory" != "$default_reflex_runner_path" ] && [ ! -e "$directory" ]; then
        echo "Path $directory doesn't exist."
      elif [ ! -w "$directory" ]; then
        echo "Path $directory exists but cannot be written to."
      elif [ ! -d "$directory" ]; then
        echo "Path $directory is not a directory."
      else
        break
      fi
    done
  fi

  if $do_download; then
    # we will create the default directory for the user if we can, just not other directories for now
    if mkdir -p $directory ; then
      directory=${directory%/} # remove trailing slash
      echo "Getting location of latest ReflexRunner release."
      download_link=$(get_download_link)
      file_name=${download_link##*/} # extract file name from full link

      echo "Downloading $file_name to $directory. Download started at" $(date +"%T")"."
      curl -qLSs -o "$directory/$file_name" $download_link
      validate_curl_response $? 200 "There was a problem downloading $file_name from $download_link."

      echo "Done downloading."
      echo "Setting up ReflexRunner."
      unzip -qq "$directory/$file_name"
      reflex_runner_path=$(find_in_filesystem ReflexRunner bin/ReflexRunner $directory)
    else
      echo "Unable to create directory $directory."
      exit 1
    fi
  fi
fi

set_vars=$(prompt_yes_no "Would you like to launch a new session with convenient environment variables set?")
if ! $set_vars; then
  exit 0
fi

# write the export statements to a file to be sourced later
env_var_filename=".rapture_client.$RANDOM.env"

if [ -n "$reflex_runner_path" ] && [ !$reflex_runner_is_in_path ] ; then
  add_to_path=$(dirname $reflex_runner_path)
  echo "export PATH=$PATH:$add_to_path" >> $env_var_filename
fi

tutorial_var_ls=$(ls $RAPTURE_TUTORIAL_CSV)
if [[ "$tutorial_var_ls" != "$RAPTURE_TUTORIAL_CSV" ]]; then
  echo "Searching your filesystem for Tutorial resources. To avoid this search in the future, set the environment variable RAPTURE_TUTORIAL_CSV to the full path to introDataInbound.csv"
  csv_path=$(find_in_filesystem introDataInbound.csv RaptureTutorials/Intro01/resources/introDataInbound.csv)
  if [ -n $csv_path ] ; then
    echo "Found introDataInbound.csv at $csv_path."
    echo "export RAPTURE_TUTORIAL_CSV=$csv_path" >> $env_var_filename
  fi
fi

read -p "Enter Etienne User: " user
read -s -p "Enter Etienne Password: " pass
echo $'\n'

hashpass=$(echo -n $pass | md5)

login_url="$HOST/login/login?user=$user&password=$hashpass"
env_vars_url="$HOST/curtisscript/getEnvInfo?username=$user"

curl_results=$( curl -qSsw '\n%{http_code}' --cookie-jar .cookiefile $login_url )
validate_curl_response $? $(echo "$curl_results" | tail -n1) "There was a problem logging into $HOST."

# get environment variable data, append HTTP status code in separate line
curl_results=$( curl -qSsw '\n%{http_code}' --cookie .cookiefile $env_vars_url )
validate_curl_response $? $(echo "$curl_results" | tail -n1) "There was a problem retrieving the environment variables from $HOST."
env_data=$(echo "$curl_results" | sed \$d) #strip http status


IFS='|' read -a env_var_array <<< "$env_data"

for pair in "${env_var_array[@]}"
do
  IFS=',' read -a pair_array <<< "$pair"

  array_length=${#pair_array[@]}
  if [[ $array_length -ne 2 ]] ; then
    echo "The data retrieved from $env_vars_url is invalid."
    exit 1
  fi

  var_name=${pair_array[0]}
  var_val=${pair_array[1]}

  echo "export $var_name=$var_val" >> $env_var_filename
done



# Also write a welcome banner to the file and change the prompt so it's easier for the user
# to know that they are in a screen session.
cat << 'EOF' >> $env_var_filename

#banner
BLUE="\033[01;34m"
WHITE="\033[01;37m"
echo -e "${BLUE}******************************************************************************"
echo -e "${BLUE}**                                                                          **"
echo -e "${BLUE}**                            Welcome To Rapture                            **"
echo -e "${BLUE}**                                                                          **"
echo -e "${BLUE}******************************************************************************"
echo -e "\033[0m \033[39m"

#prompt
PS1="Rapture: \W \u\$ "
EOF

# start up a new session in screen and source the file we wrote
screen -h 2000 -S Rapture sh -c "exec /bin/bash -init-file ./$env_var_filename"

# will execute after screen session exits
rm $env_var_filename
