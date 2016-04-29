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
  $strip_components = "0",
  $registration_type = "require_once",
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
        ensure           => present,
        instance         => $instance,
        source           => $source,
        strip_components => $strip_components,
        doc_root         => $doc_root, 
        #before          => File_line["${extension_name}_include"],
        notify           => Exec["set_${extension_name}_perms"],
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
  case $registration_type {
    require_once: {
      case $install_type {
        tar:      { $line = "require_once( \"\$IP/extensions/${extension_name}/${extension_name}.php\" );" }
        git:      { $line = "require_once( \"\$IP/extensions/${extension_name}/${extension_name}.php\" );" }
        composer: { $line = "# ${extension_name} included via Composer" }
        default:  { fail("Unknown extension install type. Allowed values: tar")}
      }
    }
    wfLoadExtension: {
      case $install_type {
        tar:      { $line = "wfLoadExtension( \"${extension_name}\" );" }
        git:      { $line = "wfLoadExtension( \"${extension_name}\" );" }
        composer: { $line = "# ${extension_name} included via Composer" }
        default:  { fail("Unknown extension install type. Allowed values: tar")}
      }
    }
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
        notify    =>  File_line["${extension_name}_footer"],
      }
    }
  } else {
    # dummy exec for calling database update
    exec { "${extension_name}_config_done":
      command   =>  "/bin/true",
      subscribe =>  File_line["${extension_name}_include"],
      notify    =>  File_line["${extension_name}_footer"],
    }
  }
  
  ## Add extension footer to LocalSettings.php
  file_line { "${extension_name}_footer":
    line    =>  "## ======== ${extension_name} ========\n\n",
    ensure  =>  $ensure,
    path    =>  $localsettings_path,
    notify  =>  Exec["${extension_name}_update_database"],
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
  # Class['mysql::server'] -> Class['mediawiki']
  #Class['mysql::config'] -> Class['mediawiki']
  
  # Add MySQL packages to apt
  apt::source { 'mysql-server-56':
    comment  => 'MySQL Server 5.6.x',
    location => "http://repo.mysql.com/apt/<%= $::osfamily.downcase %>",
    release  => "<%= $::lsbdistcodename.downcase %>",
    repos    => 'mysql-5.6',
    architecture => "<%= $::architecture.downcase %>",
    key      => {
      id     => '5072E1F5',
      content => '-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v1.4.9 (SunOS)

mQGiBD4+owwRBAC14GIfUfCyEDSIePvEW3SAFUdJBtoQHH/nJKZyQT7h9bPlUWC3
RODjQReyCITRrdwyrKUGku2FmeVGwn2u2WmDMNABLnpprWPkBdCk96+OmSLN9brZ
fw2vOUgCmYv2hW0hyDHuvYlQA/BThQoADgj8AW6/0Lo7V1W9/8VuHP0gQwCgvzV3
BqOxRznNCRCRxAuAuVztHRcEAJooQK1+iSiunZMYD1WufeXfshc57S/+yeJkegNW
hxwR9pRWVArNYJdDRT+rf2RUe3vpquKNQU/hnEIUHJRQqYHo8gTxvxXNQc7fJYLV
K2HtkrPbP72vwsEKMYhhr0eKCbtLGfls9krjJ6sBgACyP/Vb7hiPwxh6rDZ7ITnE
kYpXBACmWpP8NJTkamEnPCia2ZoOHODANwpUkP43I7jsDmgtobZX9qnrAXw+uNDI
QJEXM6FSbi0LLtZciNlYsafwAPEOMDKpMqAK6IyisNtPvaLd8lH0bPAnWqcyefep
rv0sxxqUEMcM3o7wwgfN83POkDasDbs3pjwPhxvhz6//62zQJ7Q2TXlTUUwgUmVs
ZWFzZSBFbmdpbmVlcmluZyA8bXlzcWwtYnVpbGRAb3NzLm9yYWNsZS5jb20+iGkE
ExECACkCGyMGCwkIBwMCBBUCCAMEFgIDAQIeAQIXgAIZAQUCUwHUZgUJGmbLywAK
CRCMcY07UHLh9V+DAKCjS1gGwgVI/eut+5L+l2v3ybl+ZgCcD7ZoA341HtoroV3U
6xRD09fUgeq0O015U1FMIFBhY2thZ2Ugc2lnbmluZyBrZXkgKHd3dy5teXNxbC5j
b20pIDxidWlsZEBteXNxbC5jb20+iG8EMBECAC8FAk53Pa0oHSBidWlsZEBteXNx
bC5jb20gd2lsbCBzdG9wIHdvcmtpbmcgc29vbgAKCRCMcY07UHLh9bU9AJ9xDK0o
xJFL9vTl9OSZC4lX0K9AzwCcCrS9cnJyz79eaRjL0s2r/CcljdyIZQQTEQIAHQUC
R6yUtAUJDTBYqAULBwoDBAMVAwIDFgIBAheAABIJEIxxjTtQcuH1B2VHUEcAAQGu
kgCffz4GUEjzXkOi71VcwgCxASTgbe0An34LPr1j9fCbrXWXO14msIADfb5piEwE
ExECAAwFAj4+o9EFgwlmALsACgkQSVDhKrJykfIk4QCfWbEeKN+3TRspe+5xKj+k
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
AcOphrnJ
=443I
-----END PGP PUBLIC KEY BLOCK-----',
    },
  }
  ->
  exec { "apt-update-mysql":
    command => "/usr/bin/apt-get update"
  }
  
  class { 'apache': 
    mpm_module => 'prefork',
  }
  class { 'apache::mod::php': }
  
  
  # Manages the mysql server package and service by default
  class { 'mysql::server':
    require => Apt::Source['mysql-server-56'],
    package_name => 'mysql-server-5.6',
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

  # Install packages as defined in params.pp
  package { $mediawiki::params::packages:
    ensure  => $package_ensure,
  }
  Package[$mediawiki::params::packages] ~> Service<| title == $mediawiki::params::apache |>
  
  #file { '/etc/profile.d/set-composer_home.sh':
  #  content => 'export COMPOSER_HOME=/usr/local/bin'
  #}
  
  # Install composer after php has been installed
  class { 'composer':
    command_name => 'composer',
    target_dir   => '/usr/local/bin',
    auto_update => false,
    version => '1.0.0-alpha11',
    require => Package[$mediawiki::params::packages],
  }

  # Make sure the directories and files common for all instances are included
  file { 'mediawiki_conf_dir':
    ensure  => 'directory',
    path    => $mediawiki::params::conf_dir,
    owner   => $mediawiki::params::apache_user,
    group   => $mediawiki::params::apache_user,
    mode    => '0755',
    require => Package[$mediawiki::params::packages],
  }  
  
  # Download and install MediaWiki from a tarball using aria with 4 connections
  exec { "get-mediawiki":
    cwd       => $temp_dir,
    command   => "/usr/bin/aria2c -s 4 ${tarball_url}/${tarball}",
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
