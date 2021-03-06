asdf_version() {
  echo "0.2.1"
}

asdf_dir() {
  if [ -z $ASDF_DIR ]; then
    local current_script_path=${BASH_SOURCE[0]}
    export ASDF_DIR=$(cd $(dirname $(dirname $current_script_path)); echo $(pwd))
  fi

  echo $ASDF_DIR
}

get_install_path() {
  local plugin=$1
  local install_type=$2
  local version=$3
  mkdir -p $(asdf_dir)/installs/${plugin}

  if [ $install_type = "version" ]
  then
    echo $(asdf_dir)/installs/${plugin}/${version}
  else
    echo $(asdf_dir)/installs/${plugin}/${install_type}-${version}
  fi
}

list_installed_versions() {
  local plugin_name=$1
  local plugin_path=$(get_plugin_path $plugin_name)

  local plugin_installs_path=$(asdf_dir)/installs/${plugin_name}

  if [ -d $plugin_installs_path ]; then
    for install in $(ls -d ${plugin_installs_path}/*/ 2>/dev/null); do
      echo "$(basename $install)"
    done
  fi
}

check_if_plugin_exists() {
  # Check if we have a non-empty argument
  if [ -z "${1+set}" ]; then
    display_error "No such plugin"
    exit 1
  fi

  if [ ! -d $(asdf_dir)/plugins/$1 ]; then
    display_error "No such plugin"
    exit 1
  fi
}

check_if_version_exists() {
  local plugin=$1
  local version=$2
  local version_dir=$(asdf_dir)/installs/$plugin/$version

  # if version starts with path: use that directory
  if [ "${version/path:}" != "$version" ]; then
      version_dir=$(echo $version | cut -d: -f 2)
  fi

  if [ ! -d $version_dir ]; then
    display_error "version $version is not installed for $plugin"
    exit 1
  fi
}

get_plugin_path() {
  echo $(asdf_dir)/plugins/$1
}

display_error() {
  echo >&2 $1
}

get_version_in_dir() {
  local plugin_name=$1
  local search_path=$2
  local legacy_filenames=$3

  local asdf_version=$(parse_asdf_version_file "$search_path/.tool-versions" $plugin_name)

  if [ -n "$asdf_version" ]; then
    echo "$asdf_version|$search_path/.tool-versions"
    return 0
  fi

  for filename in $legacy_filenames; do
    local legacy_version=$(parse_legacy_version_file "$search_path/$filename" $plugin_name)

    if [ -n "$legacy_version" ]; then
      echo "$legacy_version|$search_path/$filename"
      return 0
    fi
  done
}

find_version() {
  local plugin_name=$1
  local search_path=$2

  local version=$(get_version_from_env "$plugin_name")
  if [ -n "$version" ]; then
      echo "$version"
      return 0
  fi

  local plugin_path=$(get_plugin_path "$plugin_name")
  local legacy_config=$(get_asdf_config_value "legacy_version_file")
  local legacy_list_filenames_script="${plugin_path}/bin/list-legacy-filenames"
  local legacy_filenames=""

  if [ "$legacy_config" = "yes" ] && [ -f $legacy_list_filenames_script ]; then
    legacy_filenames=$(bash "$legacy_list_filenames_script")
  fi

  while [ "$search_path" != "/" ]; do
    version=$(get_version_in_dir "$plugin_name" "$search_path" "$legacy_filenames")
    if [ -n "$version" ]; then
      echo "$version"
      return 0
    fi
    search_path=$(dirname "$search_path")
  done

  get_version_in_dir "$plugin_name" "$HOME" "$legacy_filenames"
}

get_version_from_env () {
  local plugin_name=$1
  local upcase_name=$(echo $plugin_name | tr '[a-z]' '[A-Z]')
  local version_env_var="ASDF_${upcase_name}_VERSION"
  local version=${!version_env_var}
  echo "$version"
}

parse_asdf_version_file() {
  local file_path=$1
  local plugin_name=$2

  if [ -f "$file_path" ]; then
    local version=$(grep "${plugin_name} " $file_path | sed -e "s/^${plugin_name} //")
    if [ -n "$version" ]; then
      echo $version
      return 0
    fi
  fi
}

parse_legacy_version_file() {
  local file_path=$1
  local plugin_name=$2

  local plugin_path=$(get_plugin_path "$plugin_name")
  local parse_legacy_script="${plugin_path}/bin/parse-legacy-file"

  if [ -f $file_path ]; then
    if [ -f $parse_legacy_script ]; then
      echo $(bash "$parse_legacy_script" "$file_path")
    else
      echo $(cat $file_path)
    fi
  fi
}

get_preset_version_for() {
  local plugin_name=$1
  local search_path=$(pwd)
  local version_and_path=$(find_version "$plugin_name" "$search_path")
  local version=$(cut -d '|' -f 1 <<< "$version_and_path");

  echo "$version"
}

get_asdf_config_value_from_file() {
    local config_path=$1
    local key=$2

    if [ ! -f $config_path ]; then
        return 0
    fi

    local result=$(grep -E "^\s*$key\s*=" $config_path | awk -F '=' '{ gsub(/ /, "", $2); print $2 }')
    if [ -n "$result" ]; then
        echo $result
    fi
}

get_asdf_config_value() {
    local key=$1
    local config_path=${AZDF_CONFIG_FILE:-"$HOME/.asdfrc"}
    local default_config_path=${AZDF_CONFIG_DEFAULT_FILE:-"$(asdf_dir)/defaults"}

    local result=$(get_asdf_config_value_from_file $config_path $key)

    if [ -n "$result" ]; then
        echo $result
    else
        get_asdf_config_value_from_file $default_config_path $key
    fi
}
