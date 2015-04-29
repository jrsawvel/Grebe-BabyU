package Tags;

use strict;

use CGI qw(:standard);
use CGI::Carp qw(fatalsToBrowser);
use API::GetTags;
use API::Error;

sub tags {
    my $tmp_hash = shift;
    my $q = new CGI;
    my $request_method = $q->request_method();
    if ( $request_method eq "GET" ) {
        GetTags::get_tags();
    } 
    Error::report_error("400", "Not found", "Invalid request");  
}
1;
