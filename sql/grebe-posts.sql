-- grebe-posts.sql

-- drop table if exists grebe_posts;
create table grebe_posts (
    post_id        mediumint unsigned auto_increment primary key,
    parent_id      mediumint unsigned not null default 0, -- (refers_to) this id number shows which post the content belongs to. if type='r', then it's the post id the comment belongs to. if status='v', then it's what post the old version belongs to. 
    title          varchar(255) not null,
    uri_title      varchar(255) not null,
    markup_text    mediumtext not null,
    formatted_text mediumtext not null,
    post_type      varchar(10) not null default 'article',  -- article, note, draft
    post_status    char(1) not null default 'o',  -- (o) open, (d) deleted, (v) old version, 
    author_id      smallint unsigned not null,
    created_date   datetime, 
    modified_date  datetime,
    version        mediumint unsigned not null default 1, 
    post_digest    varchar(255),
    edit_reason    varchar(255),
    tags           varchar(255),
    index(parent_id)
) ENGINE=MyISAM;

