# Grebe MySql Database


## Add Grebe database and user.


Enter this command to get into mysql command line interface: (it will ask for the root password)

`mysql -uroot -p`

At the `mysql>` prompt, enter the following commands, one at a time:

`create database grebe;`

`create user 'grebe'@'localhost' identified by 'set_your_password_here';`

`grant all privileges on grebe.* to 'grebe'@'localhost';`

`flush privileges;`

`quit;`



## Create Tables


`cd Grebe/sql`

Execute the following commands, using the information when creating the database above:

`mysql -ugrebe -pyourpassword -D grebe < grebe-users.sql`

`mysql -ugrebe -pyourpassword -D grebe < grebe-posts.sql`

`mysql -ugrebe -pyourpassword -D grebe < grebe-tags.sql`

`mysql -ugrebe -pyourpassword -D grebe < grebe-sessionids.sql`



## Modify YAML File

`cd Grebe/yaml`

Edit `grebe.yml` and make the changes to following parameters:

`database_host: grebe`  
`database_name: grebe`  
`database_username: grebe`  
`database_password: yourpassword`  



