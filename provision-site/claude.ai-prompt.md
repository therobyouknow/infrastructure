Can you help me create some scripts to automate some tasks on my digitalocean server.


Background:
I run several Drupal 10/11 websites on this server in a very simple setup.  I want automation to:



- create some scripts to automate deploying code, backing up databases, restoring databases, running drush updb, drush cr.
- creating new release folders (and associated scripts to update symlinks)
- a script to generate all of the folder structure for a new site (but not the site files itself)

Setup I have:
I have multiple databases running on a single mysql process.
I have a folder structure for each website that looks like this:

/var/www/99/website-domain-name.com/releases
/var/www/99/website-domain-name.com/deployment_environments
/var/www/99/website-domain-name.com/settings

Where 99 is a number which is the type of client category for the site, e.g. 05 is pro-bono work I do, 09 is community work I do. It helps me separate work in my mind that I’m doing at the time, and also hide other work if I let people I collaborate with observe what I’m doing on the server.

In /var/www/99/website-domain-name.com/deployment_environments there are live and staging sub folders.

In these live and staging folders, there is a sub-path assets/public/ and in that public folder, there is a files folder - this hold all the files that a Drupal site uses to store files - the public file path. More on this later regarding how it is referenced from its Drupal site I have running on the server.

Also in those live and staging folders, there is a docroot symlink in each
In live, the docroot symlink links to a web folder in a release folder in releases for a live site.
For example: docroot -> ../../releases/2.0.4/code/web
In staging the docroot symlink links to a web folder in a release folder in releases for a staging site.




In /var/www/99/website-domain-name.com/settings I have 2 folders named 1 and 2. In each of these folders, there is a settings.local.php which has settings and credentials for a database. There are 2 databases. By having 2 folders 1 and 2, I have a settings.local.php for database 1 and database 2. More on how this is referenced from its Drupal site I have running on the server.
