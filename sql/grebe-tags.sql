
-- drop table if exists grebe_tags;
create table grebe_tags (
  tag_id 		mediumint unsigned NOT NULL auto_increment primary key,
  tag_name 		varchar(50) NOT NULL default '',
  post_id 		mediumint(8) unsigned NOT NULL default '0',
  tag_status            char(1) NOT NULL default 'x', -- o open, d deleted
  created_by 		smallint unsigned not null,
  created_date	        datetime,
  unique(tag_name,post_id)
) ENGINE=MyISAM;
