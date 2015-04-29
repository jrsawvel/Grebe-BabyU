package API::DispatchAPI;
use strict;
use API::URI;
use API::Error;

my %cgi_params = URI::get_cgi_params_from_path_info("function", "one", "two", "three", "four", "five", "six");

my $dispatch_for = {
    posts        =>   sub { return \&do_sub(       "Posts",        "posts"    ) },
    searches     =>   sub { return \&do_sub(       "Searches",     "searches"    ) },
    tags         =>   sub { return \&do_sub(       "Tags",         "tags"        ) },
    users        =>   sub { return \&do_sub(       "Users",        "users"       ) },
    versions     =>   sub { return \&do_sub(       "Versions",     "versions"    ) },
    showerror    =>   sub { return \&do_sub(       "Error",        "error"       ) },
};

sub execute {
    my $function = $cgi_params{function};
    $dispatch_for->{showerror}->() if !defined $function;
    $dispatch_for->{showerror}->($function) unless exists $dispatch_for->{$function};
    defined $dispatch_for->{$function}->();
}

sub do_sub {
    my $module = shift;
    my $subroutine = shift;
    eval "require API::$module" or Error::report_error("500", "Runtime Error:", $@);
    my %hash = %cgi_params;
    my $coderef = "$module\:\:$subroutine(\\%hash)"  or Error::report_error("500", "Runtime Error:", $@);
    eval "{ &$coderef };"  or Error::report_error("500", "Runtime Error:", $@) ;
}

1;
