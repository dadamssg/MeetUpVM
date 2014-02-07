MeetUpVM
========
This is a vagrant/puppet configuration to run Debain Wheezy 7.2 x64 with Virtualbox 4.3 at http://13.13.13.13

It will include the following:

 - git
 - vim
 - apache
 	- vhost: awesomeapp.dev 
 - php 5.5
 - composer
 - xdebug
 - PostgreSQL 9.3
 	- root password: root
 	- db name: meetup
 	- db user
	 	- username: root
	 	- password: root

---
###Required

1. [Vagrant](http://www.vagrantup.com/downloads.html)
2. [Virtualbox](https://www.virtualbox.org/wiki/Downloads)

---

If you don't want to have to manually edit your `hosts` file, download this [Vagrant::Hostupdater](https://github.com/cogitatio/vagrant-hostsupdater) plugin first. `vagrant plugin install vagrant-hostsupdater`

---

1. Clone/download the repo

2. `cd` into it in a terminal

3. Run `vagrant up`, *this will take a while the first time*

4. After provisioning, you should be able to go to [http://13.13.13.13](http://13.13.13.13) in your browser and see an "It works!" page

4. SSH into it, `vagrant ssh`

5. Go to the web root, `cd /var/www`

6. Delete the **awesomeapp** directory, `rm -rf awesomeapp`

6. Install Laravel in its place, `composer create-project laravel/laravel awesomeapp --prefer-dist`

7. Update your virtual host, `sudo vim /etc/apache2/sites-enabled/25-8Kbwh6BhYDLV.conf` 

	*Note* - your conf file may be named something different but equally random. `cd` into the `/etc/apache2/sites-enabled` directory and run an `ls` to see what yours is called. 
	
	**Super Quick VIM tutorial**: press `i` to go into "insert mode", use your arrow keys to navigate to where you want to start typing, type some stuff, press your `Esc` key to get out of "insert mode", enter `:wq` to write and quit the file. 

	Your conf file should like like this(notice the appendage of `public` to `/var/www/awesomeapp`)

	```ApacheConf
	# ************************************
	# Vhost template in module puppetlabs-apache
	# Managed by Puppet
	# ************************************

	<VirtualHost *:80>
	  ServerName awesomeapp.dev

	  ## Vhost docroot
	  DocumentRoot "/var/www/awesomeapp/public"



	  ## Directories, there should at least be a declaration for /var/www/awesomeapp


	  <Directory "/var/www/awesomeapp/public">
	    Options Indexes FollowSymLinks MultiViews
	    AllowOverride All
	    Order allow,deny
	    Allow from all
	  </Directory>

	  ## Load additional static includes


	  ## Logging
	  ErrorLog "/var/log/apache2/8Kbwh6BhYDLV_error.log"
	  ServerSignature Off
	  CustomLog "/var/log/apache2/8Kbwh6BhYDLV_access.log" combined




	  ## Server aliases
	  ServerAlias www.awesomeapp.dev

	  ## SetEnv/SetEnvIf for environment variables
	  SetEnv APP_ENV dev
	</VirtualHost>
	```

8. Restart apache, `sudo service apache2 restart`. 

9. You should now be able to go to [http://awesomeapp.dev](http://awesomeapp.dev) in your browser and see Laravel running. 

10. If you see a blank screen you probably need to change the permissions on Laravel's storage directory. 

	If you're on a mac...In another terminal outside of your vm `cd` into your `awesomeapp` directory and update the permissions with `sudo chmod -R 777 app/storage`. 

	If you're on windows you should be able to right click on the **storage** directory and manually change the settings. 
