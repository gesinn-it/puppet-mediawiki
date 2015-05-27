# Class: mediawiki
#
# This class includes all resources regarding installation and configuration
# that needs to be performed exactly once and is therefore not mediawiki
# instance specific.
#
# === Parameters
#
# [*server_name*]      - the host name of the server
# [*admin_email*]      - email address Apache will display when rendering error page
# [*db_root_password*] - password for mysql root user
# [*doc_root*]         - the DocumentRoot directory used by Apache
# [*tarball_url*]      - the url to fetch the mediawiki tar archive
# [*package_ensure*]   - state of the package
# [*max_memory*]       - a memcached memory limit
#
# === Examples
#
# class { 'mediawiki':
#   server_name      => 'www.example.com',
#   admin_email      => 'admin@puppetlabs.com',
#   db_root_password => 'really_really_long_password',
#   max_memory       => '1024'
# }
#
# mediawiki::instance { 'my_wiki1':
#   db_name     => 'wiki1_user',
#   db_password => 'really_long_password',
# }
#
## === Authors
#
# Martin Dluhos <martin@gnu.org>
# Alexander Gesinn
#

define mediawiki::manage_extension(
  $ensure,
  $instance,
  $source,
  $source_version = "",
  $doc_root,
  $extension_name,
  $extension_config = "",
  $install_type,
 ){

  $localsettings_path = "${doc_root}/${instance}/LocalSettings.php"
 
  ## Install extension
  case $install_type {
    composer: {
      # implemented as exec() as composer requires COMPOSER_PATH set
      exec { "${extension_name}":
        command     =>  "/usr/local/bin/composer require --update-no-dev --prefer-dist ${source} ${source_version}",
        cwd         =>  "${doc_root}/${instance}",
        environment =>  ["COMPOSER_HOME=/usr/local/bin", "COMPOSER_CACHE_DIR=/vagrant_share", "COMPOSER_PROCESS_TIMEOUT=600"],
        notify      =>  Exec["set_${extension_name}_perms"],
        timeout     =>  600,
      }
    }
    git: {
      mediawiki_extension_git { "${extension_name}":
        ensure         => present,
        instance       => $instance,
        source         => $source,
        source_version => $source_version,
        doc_root       => $doc_root, 
        notify         => Exec["set_${extension_name}_perms"],
      }
    }
    tar: {
      mediawiki_extension { "${extension_name}":
        ensure   => present,
        instance => $instance,
        source   => $source,
        doc_root => $doc_root, 
        #before  => File_line["${extension_name}_include"],
        notify   => Exec["set_${extension_name}_perms"],
      }
    }
    default: {
      fail("Unknown extension install type. Allowed values: tar")
    }
  }
  
  ## Set File Owner
  exec{"set_${extension_name}_perms":
    command     =>  "/bin/chown -R ${mediawiki::params::apache_user}:${mediawiki::params::apache_user} ${doc_root}/${instance}",
    refreshonly =>  true,
  }

  ## Add extension header to LocalSettings.php
  file_line { "${extension_name}_header":
    line    =>  "## -------- ${extension_name} --------",
    ensure  =>  $ensure,
    path    =>  $localsettings_path,
    subscribe =>  Exec["set_${extension_name}_perms"],
  }

  ## Add extension to LocalSettings.php
  case $install_type {
    tar:      { $line = "require_once( \"\$IP/extensions/${extension_name}/${extension_name}.php\" );" }
    composer: { $line = "# ${extension_name} included via Composer" }
    default:  { fail("Unknown extension install type. Allowed values: tar")}
  }

  file_line { "${extension_name}_include":
    line    =>  $line,
    ensure  =>  $ensure,
    path    =>  $localsettings_path,
    subscribe =>  File_line["${extension_name}_header"],
  }
  
  ## Add extension configuration parameter to LocalSettings.php
  if size($extension_config) > 0 {
    each($extension_config) |$line| {
      $uid = md5($line)
      file_line { "${extension_name}_config_${uid}":
        line      =>  $line,
        ensure    =>  $ensure,
        path      =>  $localsettings_path,
        subscribe =>  File_line["${extension_name}_include"],
        notify    => Exec["${extension_name}_update_database"],
      }
    }
  } else {
    # dummy exec for calling database update
    exec { "${extension_name}_config_done":
      command => "/bin/true",
      subscribe =>  File_line["${extension_name}_include"],
      notify  => Exec["${extension_name}_update_database"],
    }
  }
  
  ## Update the database
  exec { "${extension_name}_update_database":
    command     =>  "/usr/bin/php update.php --conf ../LocalSettings.php",
    cwd         =>  "${doc_root}/${instance}/maintenance",
  }
  
  ## Notify httpd service
  # File_line["${extension_name}_include"] ~> Service<| title == 'httpd' |>
}

class mediawiki (
  $server_name,
  $admin_email,
  $db_root_password,
  $doc_root       = $mediawiki::params::doc_root,
  $tarball_url    = $mediawiki::params::tarball_url,
  $tarball,
  $mediawiki_dir,
  $temp_dir       = '/tmp',
  $package_ensure = 'latest',
  $max_memory     = '2048'
  ) inherits mediawiki::params {

  $web_dir = $mediawiki::params::web_dir

  # Parse the url
  #$tarball_dir              = regsubst($tarball_url, '^.*?/(\d\.\d+).*$', '\1')
  #$tarball_name             = regsubst($tarball_url, '^.*?/(mediawiki-\d\.\d+.*tar\.gz)$', '\1')
  #$mediawiki_dir            = regsubst($tarball_url, '^.*?/(mediawiki-\d\.\d+\.\d+).*$', '\1')
  $mediawiki_install_path   = "${web_dir}/${mediawiki_dir}"
  
  # Specify dependencies
  Class['mysql::server'] -> Class['mediawiki']
  #Class['mysql::config'] -> Class['mediawiki']
  
  class { 'composer':
    command_name => 'composer',
    target_dir   => '/usr/local/bin',
    auto_update => true,
  }
  file { "/etc/environment":
    content => inline_template("COMPOSER_HOME=/usr/local/bin")
  }
  
  class { 'apache': 
    mpm_module => 'prefork',
  }
  class { 'apache::mod::php': }
  
  
  # Manages the mysql server package and service by default
  class { 'mysql::server':
    root_password => $db_root_password,
    override_options => {
      'client' => {
        'default-character-set' => 'utf8',
      },
      'mysqld' => {
        'init_connect' => 'SET collation_connection = utf8_general_ci',
        'init_connect' => 'SET NAMES utf8',
        'character-set-server' => 'utf8',
        'collation-server' => 'utf8_general_ci',
        'skip-character-set-client-handshake' => true,
      }
    }
  }

  package { $mediawiki::params::packages:
    ensure  => $package_ensure,
  }
  Package[$mediawiki::params::packages] ~> Service<| title == $mediawiki::params::apache |>

  # Make sure the directories and files common for all instances are included
  file { 'mediawiki_conf_dir':
    ensure  => 'directory',
    path    => $mediawiki::params::conf_dir,
    owner   => $mediawiki::params::apache_user,
    group   => $mediawiki::params::apache_user,
    mode    => '0755',
    require => Package[$mediawiki::params::packages],
  }  
  
  # Download and install MediaWiki from a tarball using axel with 4 connections
  exec { "get-mediawiki":
    cwd       => $temp_dir,
    command   => "/usr/bin/axel -n 4 ${tarball_url}/${tarball}",
    creates   => "${temp_dir}/${tarball}",
    subscribe => File['mediawiki_conf_dir'],
    timeout   => 0,
  }
    
  exec { "unpack-mediawiki":
    cwd       => $temp_dir,
    command   => "/bin/tar -xzf ${tarball} -C ${web_dir}",
    creates   => $mediawiki_install_path,
    subscribe => Exec['get-mediawiki'],
    timeout   => 0,
  }
  
  class { 'memcached':
    max_memory => $max_memory,
    max_connections => '1024',
  }
} 
