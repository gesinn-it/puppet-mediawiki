# == Define: mediawiki::instance
#
# This defined type allows the user to create a mediawiki instance.
#
# === Parameters
#
# [*db_name*]        - name of the mediawiki instance mysql database
# [*db_user*]        - name of the mysql database user
# [*db_password*]    - password for the mysql database user
# [*ip*]             - ip address of the mediawiki web server
# [*port*]           - port on mediawiki web server
# [*server_aliases*] - an array of mediawiki web server aliases
# [*ensure*]         - the current status of the wiki instance
#                    - options: present, absent, deleted
#
# === Examples
#
# class { 'mediawiki':
#   admin_email      => 'admin@puppetlabs.com',
#   db_root_password => 'really_really_long_password',
#   max_memory       => '1024'
# }
#
# mediawiki::instance { 'my_wiki1':
#   db_password => 'really_long_password',
#   db_name     => 'wiki1',
#   db_user     => 'wiki1_user',
#   port        => '80',
#   ensure      => 'present'
# }
#
# === Authors
#
# Martin Dluhos <martin@gnu.org>
#
# === Copyright
#
# Copyright 2012 Martin Dluhos
#
define mediawiki::instance (
  $db_password,
  $db_name                = $name,
  $db_user                = "${name}_user",
  $db_prefix              = 'wk',
  $ip                     = '*',
  $port                   = '80',
  $server_aliases         = '',
  $ensure                 = 'present',
  $allow_html_email       = false,
  $additional_mail_params = 'none',
  $logo_url               = false,
  $external_smtp          = false,
  $smtp_idhost            = undef,
  $smtp_host              = undef,
  $smtp_port              = undef,
  $smtp_auth              = undef,
  $smtp_username          = undef,
  $smtp_password          = undef,
  ) {
  
  validate_re($ensure, '^(present|absent|deleted)$',
  "${ensure} is not supported for ensure.
  Allowed values are 'present', 'absent', and 'deleted'.")

  include mediawiki::params

  # MediaWiki needs to be installed before a particular instance is created
  Class['mediawiki'] -> Mediawiki::Instance[$name]

  # Make the configuration file more readable
  $admin_email             = $mediawiki::admin_email
  $db_root_password        = $mediawiki::db_root_password
  $server_name             = $mediawiki::server_name
  $doc_root                = $mediawiki::doc_root
  $mediawiki_install_path  = $mediawiki::mediawiki_install_path
  $mediawiki_conf_dir      = $mediawiki::params::conf_dir
  $mediawiki_install_files = $mediawiki::params::installation_files
  $apache_daemon           = $mediawiki::params::apache_daemon
  $apache_user             = $mediawiki::params::apache_user
  $apache_group            = $mediawiki::params::apache_user

  if $external_smtp {
    if ! $smtp_idhost   { fail("'smtp_idhost' required when 'external_smtp' is true.") }
    if ! $smtp_host     { fail("'smtp_host' required when 'external_smtp' is true.") }
    if ! $smtp_port     { fail("'smtp_port' required when 'external_smtp' is true.") }
    if ! $smtp_auth     { fail("'smtp_auth' required when 'external_smtp' is true.") }
    if ! $smtp_username { fail("'smtp_username' required when 'external_smtp' is true.") }
    if ! $smtp_password { fail("'smtp_password' required when 'external_smtp' is true.") }
    $wgsmtp = "array('host' => '${smtp_host}', 'idhost' => '${smtp_idhost}', 'port' => '${smtp_port}', 'auth' => '${smtp_auth}', 'username' => '${smtp_username}', 'password' => '${smtp_password}')"
  } else {
    $wgsmtp = false
  }

  # Figure out how to improve db security (manually done by
  # mysql_secure_installation)
  case $ensure {
    'present', 'absent': {

      file { "${doc_root}/${name}":
        source  => $mediawiki_install_path,
        recurse => true,        
        owner => $apache_user,
        group => $apache_group,
      }

      exec { "${name}-install_script":
        cwd     => "${doc_root}/${name}/maintenance",
        command => "/usr/bin/php install.php ${name} admin --pass puppet --email ${admin_email} --server http://${server_name} --scriptpath /${name} --dbtype mysql --dbserver localhost --installdbuser root --installdbpass ${db_root_password} --dbname ${db_name} --dbuser ${db_user} --dbpass ${db_password} --db-prefix ${db_prefix} --confpath ${doc_root}/${name} --lang en",
        creates => "${doc_root}/${name}/LocalSettings.php",
        group   => $apache_group,
      }
      
      # Only for MW < 1.25
      exec { "${name}-composer.json":
        command => "cp ${doc_root}/${name}/composer-example.json ${doc_root}/${name}/composer.json",
        path    => "/usr/local/bin/:/bin/",
        onlyif  => "test -f ${doc_root}/${name}/composer-example.json",
      }
      File["${doc_root}/${name}"] -> Exec["${name}-install_script"]
      Exec["${name}-install_script"] -> Exec["${name}-composer.json"]


      # MediaWIki Custom Logo
      /*
      if $logo_url {
        file_line{"${name}_logo_url":
          path  =>  "${mediawiki_conf_dir}/${name}/LocalSettings.php",
          line  =>  "\$wgLogo = '${logo_url}';",
        }
      }
      */

      # MediaWiki DefaultSettings
      /*
      file { "${mediawiki_conf_dir}/${name}/includes/DefaultSettings.php":
        ensure  =>  present,
        content =>  template('mediawiki/DefaultSettings.php.erb'),  
      }
      */

      # Each instance needs a separate folder to upload images
      /*
      file { "${mediawiki_conf_dir}/${name}/images":
        ensure   => directory,
        group => $::operatingsystem ? {
          /(?i)(redhat|centos)/ => 'apache',
          /(?i)(debian|ubuntu)/ => 'www-data',
          default               => undef,
        }
      }
      */
      
      # Ensure that mediawiki configuration files are included in each instance.
      /*
      mediawiki::symlinks { $name:
        conf_dir      => $mediawiki_conf_dir,
        install_files => $mediawiki_install_files,
        target_dir    => $mediawiki_install_path,
      }
      */

      # Symlink for the mediawiki instance directory
      /*
      file { "${doc_root}/${name}":
        ensure   => link,
        target   => "${mediawiki_conf_dir}/${name}",
        require  => File["${mediawiki_conf_dir}/${name}"],
      }
      */
      
     
      # Each instance has a separate vhost configuration
      apache::vhost { $name:
        port          => $port,
        docroot       => $doc_root,
        serveradmin   => $admin_email,
        servername    => $server_name,
        vhost_name    => $ip,
        serveraliases => $server_aliases,
        ensure        => $ensure,
      }
    }
    'deleted': {
      
      # Remove the MediaWiki instance directory if it is present
      file { "${mediawiki_conf_dir}/${name}":
        ensure  => absent,
        recurse => true,
        purge   => true,
        force   => true,
      }

      # Remove the symlink for the mediawiki instance directory
      file { "${doc_root}/${name}":
        ensure   => absent,
        recurse  => true,
      }

      mysql::db { $db_name:
        user     => $db_user,
        password => $db_password,
        host     => 'localhost',
        grant    => ['all'],
        ensure   => 'absent',
      }

      apache::vhost { $name:
        port          => $port,
        docroot       => $doc_root,
        ensure        => 'absent',
      } 
    }
  }
}
