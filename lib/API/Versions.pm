package Versions;

use strict;

use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);
use API::GetVersions;
use API::CompareVersions;
use API::Error;

sub versions {
    my $tmp_hash = shift;

    my $q = new CGI;
    my $request_method = $q->request_method();

    if ( $request_method eq "GET" ) {
        if ( $tmp_hash->{two} ) {
            CompareVersions::compare_versions($tmp_hash->{one}, $tmp_hash->{two});
        } else {
            GetVersions::get_versions($tmp_hash->{one});
        } 
    }

    Error::report_error("400", "Not found", "Invalid request");  
}
1;
