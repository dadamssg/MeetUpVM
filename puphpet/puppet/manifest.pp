## Begin Server manifest

if $server_values == undef {
  $server_values = hiera('server', false)
}

# Ensure the time is accurate, reducing the possibilities of apt repositories
# failing for invalid certificates
include '::ntp'

Exec { path => [ '/bin/', '/sbin/', '/usr/bin/', '/usr/sbin/' ] }
group { 'puppet':   ensure => present }
group { 'www-data': ensure => present }

user { $::ssh_username:
  shell  => '/bin/bash',
  home   => "/home/${::ssh_username}",
  ensure => present
}

user { ['apache', 'nginx', 'httpd', 'www-data']:
  shell  => '/bin/bash',
  ensure => present,
  groups => 'www-data',
  require => Group['www-data']
}

file { "/home/${::ssh_username}":
    ensure => directory,
    owner  => $::ssh_username,
}

# copy dot files to ssh user's home directory
exec { 'dotfiles':
  cwd     => "/home/${::ssh_username}",
  command => "cp -r /vagrant/puphpet/files/dot/.[a-zA-Z0-9]* /home/${::ssh_username}/ \
              && chown -R ${::ssh_username} /home/${::ssh_username}/.[a-zA-Z0-9]* \
              && cp -r /vagrant/puphpet/files/dot/.[a-zA-Z0-9]* /root/",
  onlyif  => 'test -d /vagrant/puphpet/files/dot',
  returns => [0, 1],
  require => User[$::ssh_username]
}

case $::osfamily {
  # debian, ubuntu
  'debian': {
    class { 'apt': }

    Class['::apt::update'] -> Package <|
        title != 'python-software-properties'
    and title != 'software-properties-common'
    |>

    ensure_packages( ['augeas-tools'] )
  }
  # redhat, centos
  'redhat': {
    class { 'yum': extrarepo => ['epel'] }

    class { 'yum::repo::rpmforge': }
    class { 'yum::repo::repoforgeextras': }

    Class['::yum'] -> Yum::Managed_yumrepo <| |> -> Package <| |>

    if defined(Package['git']) == false {
      package { 'git':
        ensure  => latest,
        require => Class['yum::repo::repoforgeextras']
      }
    }

    exec { 'bash_git':
      cwd     => "/home/${::ssh_username}",
      command => "curl https://raw.github.com/git/git/master/contrib/completion/git-prompt.sh > /home/${::ssh_username}/.bash_git",
      creates => "/home/${::ssh_username}/.bash_git"
    }

    exec { 'bash_git for root':
      cwd     => '/root',
      command => "cp /home/${::ssh_username}/.bash_git /root/.bash_git",
      creates => '/root/.bash_git',
      require => Exec['bash_git']
    }

    file_line { 'link ~/.bash_git':
      ensure  => present,
      line    => 'if [ -f ~/.bash_git ] ; then source ~/.bash_git; fi',
      path    => "/home/${::ssh_username}/.bash_profile",
      require => [
        Exec['dotfiles'],
        Exec['bash_git'],
      ]
    }

    file_line { 'link ~/.bash_git for root':
      ensure  => present,
      line    => 'if [ -f ~/.bash_git ] ; then source ~/.bash_git; fi',
      path    => '/root/.bashrc',
      require => [
        Exec['dotfiles'],
        Exec['bash_git'],
      ]
    }

    file_line { 'link ~/.bash_aliases':
      ensure  => present,
      line    => 'if [ -f ~/.bash_aliases ] ; then source ~/.bash_aliases; fi',
      path    => "/home/${::ssh_username}/.bash_profile",
      require => File_line['link ~/.bash_git']
    }

    file_line { 'link ~/.bash_aliases for root':
      ensure  => present,
      line    => 'if [ -f ~/.bash_aliases ] ; then source ~/.bash_aliases; fi',
      path    => '/root/.bashrc',
      require => File_line['link ~/.bash_git for root']
    }

    ensure_packages( ['augeas'] )
  }
}

if $php_values == undef {
  $php_values = hiera('php', false)
}

case $::operatingsystem {
  'debian': {
    include apt::backports

    add_dotdeb { 'packages.dotdeb.org': release => $lsbdistcodename }

    if is_hash($php_values) {
      # Debian Squeeze 6.0 can do PHP 5.3 (default) and 5.4
      if $lsbdistcodename == 'squeeze' and $php_values['version'] == '54' {
        add_dotdeb { 'packages.dotdeb.org-php54': release => 'squeeze-php54' }
      }
      # Debian Wheezy 7.0 can do PHP 5.4 (default) and 5.5
      elsif $lsbdistcodename == 'wheezy' and $php_values['version'] == '55' {
        add_dotdeb { 'packages.dotdeb.org-php55': release => 'wheezy-php55' }
      }
    }

    $server_lsbdistcodename = downcase($lsbdistcodename)

    apt::force { 'git':
      release => "${server_lsbdistcodename}-backports",
      timeout => 60
    }
  }
  'ubuntu': {
    apt::key { '4F4EA0AAE5267A6C':
      key_server => 'hkp://keyserver.ubuntu.com:80'
    }
    apt::key { '4CBEDD5A':
      key_server => 'hkp://keyserver.ubuntu.com:80'
    }

    apt::ppa { 'ppa:pdoes/ppa': require => Apt::Key['4CBEDD5A'] }

    if is_hash($php_values) {
      # Ubuntu Lucid 10.04, Precise 12.04, Quantal 12.10 and Raring 13.04 can do PHP 5.3 (default <= 12.10) and 5.4 (default <= 13.04)
      if $lsbdistcodename in ['lucid', 'precise', 'quantal', 'raring'] and $php_values['version'] == '54' {
        if $lsbdistcodename == 'lucid' {
          apt::ppa { 'ppa:ondrej/php5-oldstable': require => Apt::Key['4F4EA0AAE5267A6C'], options => '' }
        } else {
          apt::ppa { 'ppa:ondrej/php5-oldstable': require => Apt::Key['4F4EA0AAE5267A6C'] }
        }
      }
      # Ubuntu Precise 12.04, Quantal 12.10 and Raring 13.04 can do PHP 5.5
      elsif $lsbdistcodename in ['precise', 'quantal', 'raring'] and $php_values['version'] == '55' {
        apt::ppa { 'ppa:ondrej/php5': require => Apt::Key['4F4EA0AAE5267A6C'] }
      }
      elsif $lsbdistcodename in ['lucid'] and $php_values['version'] == '55' {
        err('You have chosen to install PHP 5.5 on Ubuntu 10.04 Lucid. This will probably not work!')
      }
    }
  }
  'redhat', 'centos': {
    if is_hash($php_values) {
      if $php_values['version'] == '54' {
        class { 'yum::repo::remi': }
      }
      # remi_php55 requires the remi repo as well
      elsif $php_values['version'] == '55' {
        class { 'yum::repo::remi': }
        class { 'yum::repo::remi_php55': }
      }
    }
  }
}

if !empty($server_values['packages']) {
  ensure_packages( $server_values['packages'] )
}

define add_dotdeb ($release){
   apt::source { $name:
    location          => 'http://packages.dotdeb.org',
    release           => $release,
    repos             => 'all',
    required_packages => 'debian-keyring debian-archive-keyring',
    key               => '89DF5277',
    key_server        => 'keys.gnupg.net',
    include_src       => true
  }
}

## Begin MailCatcher manifest

if $mailcatcher_values == undef {
  $mailcatcher_values = hiera('mailcatcher', false)
}

if $mailcatcher_values['install'] != undef and $mailcatcher_values['install'] == 1 {
  $mailcatcher_path       = $mailcatcher_values['settings']['path']
  $mailcatcher_smtp_ip    = $mailcatcher_values['settings']['smtp_ip']
  $mailcatcher_smtp_port  = $mailcatcher_values['settings']['smtp_port']
  $mailcatcher_http_ip    = $mailcatcher_values['settings']['http_ip']
  $mailcatcher_http_port  = $mailcatcher_values['settings']['http_port']
  $mailcatcher_log        = $mailcatcher_values['settings']['log']

  class { 'mailcatcher':
    mailcatcher_path => $mailcatcher_path,
    smtp_ip          => $mailcatcher_smtp_ip,
    smtp_port        => $mailcatcher_smtp_port,
    http_ip          => $mailcatcher_http_ip,
    http_port        => $mailcatcher_http_port,
  }

  if $::osfamily == 'redhat' and ! defined(Iptables::Allow["tcp/${mailcatcher_smtp_port}"]) {
    iptables::allow { "tcp/${mailcatcher_smtp_port}":
      port     => $mailcatcher_smtp_port,
      protocol => 'tcp'
    }
  }

  if $::osfamily == 'redhat' and ! defined(Iptables::Allow["tcp/${mailcatcher_http_port}"]) {
    iptables::allow { "tcp/${mailcatcher_http_port}":
      port     => $mailcatcher_http_port,
      protocol => 'tcp'
    }
  }

  if ! defined(Class['supervisord']) {
    class { 'supervisord':
      install_pip => true,
    }
  }

  $supervisord_mailcatcher_options = sort(join_keys_to_values({
    ' --smtp-ip'   => $mailcatcher_smtp_ip,
    ' --smtp-port' => $mailcatcher_smtp_port,
    ' --http-ip'   => $mailcatcher_http_ip,
    ' --http-port' => $mailcatcher_http_port
  }, ' '))

  $supervisord_mailcatcher_cmd = "mailcatcher ${supervisord_mailcatcher_options} -f  >> ${mailcatcher_log}"

  supervisord::program { 'mailcatcher':
    command     => $supervisord_mailcatcher_cmd,
    priority    => '100',
    user        => 'mailcatcher',
    autostart   => true,
    autorestart => true,
    environment => {
      'PATH' => "/bin:/sbin:/usr/bin:/usr/sbin:${mailcatcher_path}"
    },
    require => Package['mailcatcher']
  }
}

## Begin Apache manifest

if $yaml_values == undef {
  $yaml_values = loadyaml('/vagrant/puphpet/config.yaml')
}

if $apache_values == undef {
  $apache_values = $yaml_values['apache']
}

include puphpet::params

$webroot_location = $puphpet::params::apache_webroot_location

exec { "exec mkdir -p ${webroot_location}":
  command => "mkdir -p ${webroot_location}",
  creates => $webroot_location,
}

if ! defined(File[$webroot_location]) {
  file { $webroot_location:
    ensure  => directory,
    group   => 'www-data',
    mode    => 0775,
    require => [
      Exec["exec mkdir -p ${webroot_location}"],
      Group['www-data']
    ]
  }
}

class { 'apache':
  user          => $apache_values['user'],
  group         => $apache_values['group'],
  default_vhost => $apache_values['default_vhost'],
  mpm_module    => $apache_values['mpm_module'],
  manage_user   => false,
  manage_group  => false
}

if $::osfamily == 'debian' {
  case $apache_values['mpm_module'] {
    'prefork': { ensure_packages( ['apache2-mpm-prefork'] ) }
    'worker':  { ensure_packages( ['apache2-mpm-worker'] ) }
    'event':   { ensure_packages( ['apache2-mpm-event'] ) }
  }
} elsif $::osfamily == 'redhat' and ! defined(Iptables::Allow['tcp/80']) {
  iptables::allow { 'tcp/80':
    port     => '80',
    protocol => 'tcp'
  }
}

if has_key($apache_values, 'mod_pagespeed') and $apache_values['mod_pagespeed'] == 1 {
  class { 'puphpet::apache::modpagespeed': }
}

if has_key($apache_values, 'mod_spdy') and $apache_values['mod_spdy'] == 1 {
  class { 'puphpet::apache::modspdy': }
}

if count($apache_values['vhosts']) > 0 {
  each( $apache_values['vhosts'] ) |$key, $vhost| {
    exec { "exec mkdir -p ${vhost['docroot']} @ key ${key}":
      command => "mkdir -p ${vhost['docroot']}",
      creates => $vhost['docroot'],
    }

    if ! defined(File[$vhost['docroot']]) {
      file { $vhost['docroot']:
        ensure  => directory,
        require => Exec["exec mkdir -p ${vhost['docroot']} @ key ${key}"]
      }
    }
  }
}

create_resources(apache::vhost, $apache_values['vhosts'])

define apache_mod {
  if ! defined(Class["apache::mod::${name}"]) {
    class { "apache::mod::${name}": }
  }
}

if count($apache_values['modules']) > 0 {
  apache_mod { $apache_values['modules']: }
}

## Begin PHP manifest

if $php_values == undef {
  $php_values = hiera('php', false)
}

if $apache_values == undef {
  $apache_values = hiera('apache', false)
}

if $nginx_values == undef {
  $nginx_values = hiera('nginx', false)
}

Class['Php'] -> Class['Php::Devel'] -> Php::Module <| |> -> Php::Pear::Module <| |> -> Php::Pecl::Module <| |>

if $php_prefix == undef {
  $php_prefix = $::operatingsystem ? {
    /(?i:Ubuntu|Debian|Mint|SLES|OpenSuSE)/ => 'php5-',
    default                                 => 'php-',
  }
}

if $php_fpm_ini == undef {
  $php_fpm_ini = $::operatingsystem ? {
    /(?i:Ubuntu|Debian|Mint|SLES|OpenSuSE)/ => '/etc/php5/fpm/php.ini',
    default                                 => '/etc/php.ini',
  }
}

if is_hash($apache_values) {
  include apache::params

  if has_key($apache_values, 'mod_spdy') and $apache_values['mod_spdy'] == 1 {
    $php_webserver_service_ini = 'cgi'
  } else {
    $php_webserver_service_ini = 'httpd'
  }

  $php_webserver_service = 'httpd'
  $php_webserver_user    = $apache::params::user
  $php_webserver_restart = true

  class { 'php':
    service => $php_webserver_service
  }
} elsif is_hash($nginx_values) {
  include nginx::params

  $php_webserver_service     = "${php_prefix}fpm"
  $php_webserver_service_ini = $php_webserver_service
  $php_webserver_user        = $nginx::params::nx_daemon_user
  $php_webserver_restart     = true

  class { 'php':
    package             => $php_webserver_service,
    service             => $php_webserver_service,
    service_autorestart => false,
    config_file         => $php_fpm_ini,
  }

  service { $php_webserver_service:
    ensure     => running,
    enable     => true,
    hasrestart => true,
    hasstatus  => true,
    require    => Package[$php_webserver_service]
  }
} else {
  $php_webserver_service     = undef
  $php_webserver_service_ini = undef
  $php_webserver_restart     = false

  class { 'php':
    package             => "${php_prefix}cli",
    service             => $php_webserver_service,
    service_autorestart => false,
  }
}

class { 'php::devel': }

if count($php_values['modules']['php']) > 0 {
  php_mod { $php_values['modules']['php']:; }
}
if count($php_values['modules']['pear']) > 0 {
  php_pear_mod { $php_values['modules']['pear']:; }
}
if count($php_values['modules']['pecl']) > 0 {
  php_pecl_mod { $php_values['modules']['pecl']:; }
}
if count($php_values['ini']) > 0 {
  each( $php_values['ini'] ) |$key, $value| {
    if is_array($value) {
      each( $php_values['ini'][$key] ) |$innerkey, $innervalue| {
        puphpet::ini { "${key}_${innerkey}":
          entry       => "CUSTOM_${innerkey}/${key}",
          value       => $innervalue,
          php_version => $php_values['version'],
          webserver   => $php_webserver_service_ini
        }
      }
    } else {
      puphpet::ini { $key:
        entry       => "CUSTOM/${key}",
        value       => $value,
        php_version => $php_values['version'],
        webserver   => $php_webserver_service_ini
      }
    }
  }

  if $php_values['ini']['session.save_path'] != undef {
    exec {"mkdir -p ${php_values['ini']['session.save_path']}":
      onlyif  => "test ! -d ${php_values['ini']['session.save_path']}",
    }

    file { $php_values['ini']['session.save_path']:
      ensure  => directory,
      group   => 'www-data',
      mode    => 0775,
      require => Exec["mkdir -p ${php_values['ini']['session.save_path']}"]
    }
  }
}

puphpet::ini { $key:
  entry       => 'CUSTOM/date.timezone',
  value       => $php_values['timezone'],
  php_version => $php_values['version'],
  webserver   => $php_webserver_service_ini
}

define php_mod {
  php::module { $name:
    service_autorestart => $php_webserver_restart,
  }
}
define php_pear_mod {
  php::pear::module { $name:
    use_package         => false,
    service_autorestart => $php_webserver_restart,
  }
}
define php_pecl_mod {
  php::pecl::module { $name:
    use_package         => false,
    service_autorestart => $php_webserver_restart,
  }
}

if $php_values['composer'] == 1 {
  class { 'composer':
    target_dir      => '/usr/local/bin',
    composer_file   => 'composer',
    download_method => 'curl',
    logoutput       => false,
    tmp_path        => '/tmp',
    php_package     => "${php::params::module_prefix}cli",
    curl_package    => 'curl',
    suhosin_enabled => false,
  }
}

## Begin Xdebug manifest

if $xdebug_values == undef {
  $xdebug_values = hiera('xdebug', false)
}

if is_hash($apache_values) {
  $xdebug_webserver_service = 'httpd'
} elsif is_hash($nginx_values) {
  $xdebug_webserver_service = 'nginx'
} else {
  $xdebug_webserver_service = undef
}

if $xdebug_values['install'] != undef and $xdebug_values['install'] == 1 {
  class { 'puphpet::xdebug':
    webserver => $xdebug_webserver_service
  }

  if is_hash($xdebug_values['settings']) and count($xdebug_values['settings']) > 0 {
    each( $xdebug_values['settings'] ) |$key, $value| {
      puphpet::ini { $key:
        entry       => "XDEBUG/${key}",
        value       => $value,
        php_version => $php_values['version'],
        webserver   => $xdebug_webserver_service
      }
    }
  }
}

## Begin Drush manifest

if $drush_values == undef {
  $drush_values = hiera('drush', false)
}

if $drush_values['install'] != undef and $drush_values['install'] == 1 {
  if ($drush_values['settings']['drush.tag_branch'] != undef) {
    $drush_tag_branch = $drush_values['settings']['drush.tag_branch']
  } else {
    $drush_tag_branch = ''
  }

  ## @see https://drupal.org/node/2165015
  include drush::git::drush

  ## class { 'drush::git::drush':
  ##   git_branch => $drush_tag_branch,
  ##   update     => true,
  ## }
}

## End Drush manifest

## Begin PostgreSQL manifest

if $postgresql_values == undef {
  $postgresql_values = hiera('postgresql', false)
}

if $php_values == undef {
  $php_values = hiera('php', false)
}

if is_hash($apache_values) or is_hash($nginx_values) {
  $postgresql_webserver_restart = true
} else {
  $postgresql_webserver_restart = false
}

if $postgresql_values['root_password'] {
  group { $postgresql_values['user_group']:
      ensure => present
  }

  class { 'postgresql::globals':
    version => '9.3',
    manage_package_repo => true,
    encoding => 'UTF8',
  }->
  class { 'postgresql::server':
    listen_addresses  => '*',
    manage_firewall    => true,
    postgres_password => $postgresql_values['root_password'],
    require           => Group[$postgresql_values['user_group']]
  }

  postgresql::server::pg_hba_rule { 'allow application network to access app database':
    description => "Open up postgresql for access from 0.0.0.0/0",
    type => 'host',
    database => 'all',
    user => 'all',
    address => '0.0.0.0/0',
    auth_method => 'md5',
  }

  if is_hash($postgresql_values['databases']) and count($postgresql_values['databases']) > 0 {
    create_resources(postgresql_db, $postgresql_values['databases'])
  }

  if is_hash($php_values) and ! defined(Php::Module['pgsql']) {
    php::module { 'pgsql':
      service_autorestart => $postgresql_webserver_restart,
    }
  }
}

define postgresql_db (
  $user,
  $password,
  $grant,
  $sql_file = false
) {
  if $name == '' or $user == '' or $password == '' or $grant == '' {
    fail( 'PostgreSQL DB requires that name, user, password and grant be set. Please check your settings!' )
  }

  postgresql::server::db { $name:
    user     => $user,
    password => $password,
    grant    => $grant
  }

  if $sql_file {
    $table = "${name}.*"

    exec{ "${name}-import":
      command     => "psql ${name} < ${sql_file}",
      logoutput   => true,
      refreshonly => $refresh,
      require     => Postgresql::Server::Db[$name],
      onlyif      => "test -f ${sql_file}"
    }
  }
}

if has_key($postgresql_values, 'adminer') and $postgresql_values['adminer'] == 1 and is_hash($php_values) {
  if is_hash($apache_values) {
    $postgresql_adminer_webroot_location = $puphpet::params::apache_webroot_location
  } elsif is_hash($nginx_values) {
    $postgresql_adminer_webroot_location = $puphpet::params::nginx_webroot_location
  } else {
    $postgresql_adminer_webroot_location = $puphpet::params::apache_webroot_location
  }

  class { 'puphpet::adminer':
    location => "${postgresql_adminer_webroot_location}/adminer",
    owner    => 'www-data'
  }
}

## Begin MongoDb manifest

if $mongodb_values == undef {
  $mongodb_values = hiera('mongodb', false)
}

if $php_values == undef {
  $php_values = hiera('php', false)
}

if $apache_values == undef {
  $apache_values = hiera('apache', false)
}

if $nginx_values == undef {
  $nginx_values = hiera('nginx', false)
}

if is_hash($apache_values) or is_hash($nginx_values) {
  $mongodb_webserver_restart = true
} else {
  $mongodb_webserver_restart = false
}

if has_key($mongodb_values, 'install') and $mongodb_values['install'] == 1 {
  case $::osfamily {
    'debian': {
      class {'::mongodb::globals':
        manage_package_repo => true,
      }->
      class {'::mongodb::server':
        auth => $mongodb_values['auth'],
        port => $mongodb_values['port'],
      }

      $mongodb_pecl = 'mongo'
    }
    'redhat': {
      class {'::mongodb::globals':
        manage_package_repo => true,
      }->
      class {'::mongodb::server':
        auth => $mongodb_values['auth'],
        port => $mongodb_values['port'],
      }->
      class {'::mongodb::client': }

      $mongodb_pecl = 'pecl-mongo'
    }
  }

  if is_hash($mongodb_values['databases']) and count($mongodb_values['databases']) > 0 {
    create_resources(mongodb_db, $mongodb_values['databases'])
  }

  if is_hash($php_values) and ! defined(Php::Pecl::Module[$mongodb_pecl]) {
    php::pecl::module { $mongodb_pecl:
      service_autorestart => $mariadb_webserver_restart,
      require             => Class['::mongodb::server']
    }
  }
}

define mongodb_db (
  $user,
  $password
) {
  if $name == '' or $password == '' {
    fail( 'MongoDB requires that name and password be set. Please check your settings!' )
  }

  mongodb::db { $name:
    user     => $user,
    password => $password
  }
}

# Begin beanstalkd

if $beanstalkd_values == undef {
  $beanstalkd_values = hiera('beanstalkd', false)
}

if $php_values == undef {
  $php_values = hiera('php', false)
}

if $apache_values == undef {
  $apache_values = hiera('apache', false)
}

if $nginx_values == undef {
  $nginx_values = hiera('nginx', false)
}

if is_hash($apache_values) {
  $beanstalk_console_webroot_location = "${puphpet::params::apache_webroot_location}/beanstalk_console"
} elsif is_hash($nginx_values) {
  $beanstalk_console_webroot_location = "${puphpet::params::nginx_webroot_location}/beanstalk_console"
} else {
  $beanstalk_console_webroot_location = undef
}

if has_key($beanstalkd_values, 'install') and $beanstalkd_values['install'] == 1 {
  create_resources(beanstalkd::config, {'beanstalkd' => $beanstalkd_values['settings']})

  if has_key($beanstalkd_values, 'beanstalk_console') and $beanstalkd_values['beanstalk_console'] == 1 and $beanstalk_console_webroot_location != undef and is_hash($php_values) {
    exec { 'delete-beanstalk_console-path-if-not-git-repo':
      command => "rm -rf ${beanstalk_console_webroot_location}",
      onlyif  => "test ! -d ${beanstalk_console_webroot_location}/.git"
    }

    vcsrepo { $beanstalk_console_webroot_location:
      ensure   => present,
      provider => git,
      source   => 'https://github.com/ptrofimov/beanstalk_console.git',
      require  => Exec['delete-beanstalk_console-path-if-not-git-repo']
    }
  }
}

# Begin rabbitmq

if $rabbitmq_values == undef {
  $rabbitmq_values = hiera('rabbitmq', false)
}

if $php_values == undef {
  $php_values = hiera('php', false)
}

if has_key($rabbitmq_values, 'install') and $rabbitmq_values['install'] == 1 {
  class { 'rabbitmq':
    port => $rabbitmq_values['port']
  }

  if is_hash($php_values) and ! defined(Php::Pecl::Module['amqp']) {
    php_pecl_mod { 'amqp': }
  }
}

