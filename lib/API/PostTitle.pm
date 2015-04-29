package PostTitle;

use strict;
use warnings;
use NEXT;
use API::Error;

my $pt_db_source       = Config::get_value_for("database_host");
my $pt_db_catalog      = Config::get_value_for("database_name");
my $pt_db_user_id      = Config::get_value_for("database_username");
my $pt_db_password     = Config::get_value_for("database_password");

my $dbtable_posts   = Config::get_value_for("dbtable_posts");
my $dbtable_users      = Config::get_value_for("dbtable_users");

{
    my $MAX_TITLE_LEN = Config::get_value_for("max_title_length");

    sub new {
        my ($class) = @_;

        my $ self = {
            after_title_markup => undef,
            err                => 0,
            err_str            => undef,
            title              => undef,
            posttitle          => undef,
            postid          => 0,
            username           => undef,
            markup_type        => "markdown",
            content_type       => undef
        };

        bless($self, $class);
        return $self;
    }

    sub process_title {
        my ($self, $markup) = @_;
        $self->{title} = $markup;

        if ( $self->{title} =~ m/(.+)/ ) {
            my $tmp_title = $1;
            if ( length($tmp_title) < $MAX_TITLE_LEN+1  ) {
                my $tmp_title_len = length($tmp_title);
                $self->{title} = $tmp_title;
                my $tmp_total_len = length($markup);
                $self->{after_title_markup} = substr $markup, $tmp_title_len, $tmp_total_len - $tmp_title_len;
            } else {
                $self->{title} = substr $markup, 0, $MAX_TITLE_LEN;
                my $tmp_total_len = length($markup);
                $self->{after_title_markup} = substr $markup, $MAX_TITLE_LEN, $tmp_total_len - $MAX_TITLE_LEN;
            }   
        }
        if ( !defined($self->{title}) || length($self->{title}) < 1 ) {
            $self->{err_str} .= "You must give a title for your post.";
            $self->{err} = 1;
        } else {
            # remove textile or markdown / multimarkdown heading 1 markup commands if exists.
#            my $textile = 0;
#            $textile = 1 if Utils::get_power_command_on_off_setting_for("textile", $markup, 0); 
            if ( $self->{title} =~ m/^h1\.(.+)/i ) {
                $self->{title} = $1;
                $self->{content_type} = "article";
                $self->{markup_type} = "textile";
            } elsif ( $self->{title} =~ m/^#[\s+](.+)/ ) {
                $self->{title} = $1;
                $self->{content_type} = "article";
                $self->{markup_type} = "markdown";
            } else {
                $self->{content_type} = "note";
                if ( length($self->{title}) > 75 ) {
                    $self->{after_title_markup} = $markup;
                    $self->{title} = substr $self->{title}, 0, 75;
                }
                $self->{markup_type} = "textile" if Utils::get_power_command_on_off_setting_for("textile", $markup, 0); 
            }

# will not enable namespaces for now. 24apr2014
#            if ( $self->{title} =~ m/^(.+?):(.*)$/ ) {
#                my $namespace = StrNumUtils::trim_spaces($1);
#                if ( (lc($namespace) ne lc($self->{username})) ) {
#                    $self->{err_str} .= "The text preceding the colon punctuation mark must match your username. That area is reserved for your namespace. If you don't wish to use this for your namespace, then replace the colon mark.<br /><br />";
#                    $self->{err} = 1;
#                }
#            }

            if ( _title_exists(StrNumUtils::trim_spaces($self->{title}), $self->{postid} ) ) {
                $self->{err_str} .= "Post title: \"$self->{title}\" already exists. Choose a different title.";
                $self->{err} = 1;
            }
        }
        $self->{posttitle}  = StrNumUtils::trim_spaces($self->{title});
        # $self->{posttitle}  = ucfirst($self->{posttitle});
        $self->{posttitle}  = HTML::Entities::encode_entities($self->{posttitle}, '<>');
    } # end process_title

    sub set_post_id {
        my ($self, $postid) = @_;
        $self->{postid} = $postid;
    }

    sub set_logged_in_username {
        my ($self, $username) = @_;
        $self->{username} = $username;
    } 
         
    sub get_title {
        my ($self) = @_;
        return $self->{title};
    }
         
    sub get_post_title {
        my ($self) = @_;
        return $self->{posttitle};
    }

    sub get_after_title_markup {
        my ($self) = @_;
        return $self->{after_title_markup};
    }

    sub get_content_type {
        my ($self) = @_;
        return $self->{content_type};
    }

    sub get_markup_type {
        my ($self) = @_;
        return $self->{markup_type};
    }

    sub is_error {
        my ($self) = @_;
        return $self->{err};
    }

    sub get_error_string {
        my ($self) = @_;
        return $self->{err_str};
    }
}

# todo add destroy object code

sub _title_exists {
    my $new_post_title = shift;
    my $postid = shift; # provided for updating a blog post

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);

    $new_post_title = $db->quote($new_post_title);

    my $sql;
    my $is_old_version = 0;
    my $parentid = 0;

    if ( $postid ) {
        $sql = "select parent_id, post_status from $dbtable_posts where post_id=$postid and post_type in ('article','draft','note')";
        $db->execute($sql);
        if ( $db->fetchrow ) {
            $parentid  = $db->getcol("parent_id");
            my $status = $db->getcol("post_status");
            if ( $parentid > 0 and $status eq "v" ) {
                $is_old_version = 1;
            }       
        } 
    }

    if ( $is_old_version ) {
        $sql = "select post_id from $dbtable_posts where title=$new_post_title and post_id != $parentid and post_type in ('article','draft','note') and post_status != 'v'";
    } elsif ( $postid ) { 
        $sql = "select post_id from $dbtable_posts where title=$new_post_title and post_id != $postid and post_type in ('article','draft','note') and post_status != 'v'";
    } else {
        $sql = "select post_id from $dbtable_posts where title=$new_post_title"; 
    }

    $db->execute($sql);

    my $title_already_exists = 0;

    if ( $db->fetchrow ) {
        $title_already_exists = 1; 
    } else {
        $sql = "select user_id from $dbtable_users where user_name=$new_post_title";
        $db->execute($sql);
        if ( $db->fetchrow ) {
            $title_already_exists = 1; 
        }
    }

    $db->disconnect;

    return $title_already_exists;
}

1;


