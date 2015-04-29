package Format;

use strict;
use warnings;

use Text::MultiMarkdownJRS;
use Text::Textile;
use LWP::Simple;
use HTML::TokeParser;

sub hashtag_to_link {
    my $str = shift;

    $str = " " . $str . " "; # hack to make regex work

    my @tags = ();
    my $tagsearchstr = "";
    my $tagsearchurl = Config::get_value_for("cgi_app") . "/tag/";
    if ( (@tags = $str =~ m|\s#(\w+)|gsi) ) {
            foreach (@tags) {
                next if  StrNumUtils::is_numeric($_); 
                $tagsearchstr = " <a href=\"$tagsearchurl$_\">#$_</a>";
                $str =~ s|\s#$_|$tagsearchstr|is;
        }
    }
    $str = StrNumUtils::trim_spaces($str);
    return $str;
}

sub clean_title {
    my $str = shift;
    $str =~ s|[-]||g;
    $str =~ s|[ ]|-|g;
    $str =~ s|[:]|-|g;
    $str =~ s|--|-|g;
    # only use alphanumeric, underscore, and dash in friendly link url
    $str =~ s|[^\w-]+||g;
    return $str;
}

sub permit_some_html_tags {
    my $str = shift;

    if ( $str =~ m|&lt;[\s]*iframe(.*?)&gt;|i ) {
        my $tmp = $1;
        $str =~ s|&lt;[\s]*iframe\Q$tmp&gt;|\[iframe$tmp\]|i;   
    }

    my @tags = split(/(\s+)/, Config::get_value_for("valid_html"));

    foreach (@tags) {
        my $tag = $_;
        while ( $str =~ m|&lt;[\s]*$tag(.*?)&gt;|i ) {
            my $tmp = $1;
            $str =~ s|&lt;[\s]*$tag\Q$tmp&gt;|<$tag$tmp>|i;   
        } 

        if ( $str =~ m|&lt;[\s]*/$tag&gt;|i ) {
            $str =~ s|&lt;[\s]*/$tag&gt;|</$tag>|ig;   
        }
    }

    # for tables with textile
    $str =~ s/\|&gt;\. /\|>\. /g;
    $str =~ s/\|&lt;\. /\|<\. /g;
    $str =~ s/\|&lt;&gt;\. /\|<>\. /g;

    # for images with textile
    $str =~ s/!&gt;http:/!>http:/g;
    $str =~ s/!&lt;http:/!<http:/g;

    return $str;
}

sub custom_commands {
    my $formattedcontent = shift;
    my $postid = shift;

    # q. and q..
    # hr.
    # br.
    # more. and more..
    # code. and code..
    # fence. and fence..

    $formattedcontent =~ s/^q[.][.]/\n<\/div>/igm;
    $formattedcontent =~ s/^q[.]/<div class="highlighted" markdown="1">/igm;

    $formattedcontent =~ s/^code[.][.]/<\/code><\/pre><\/div>/igm;
    $formattedcontent =~ s/^code[.]/<div class="codeClass"><pre><code>/igm;

    $formattedcontent =~ s/^fence[.][.]/<\/code><\/pre><\/div>/igm;
    $formattedcontent =~ s/^fence[.]/<div class="fenceClass"><pre><code>/igm;

    $formattedcontent =~ s/^hr[.]/<hr class="shortgrey" \/>/igm;

    $formattedcontent =~ s/^br[.]/<br \/>/igm;

    $formattedcontent =~ s/^more[.][.]/<\/more>/igm;
    $formattedcontent =~ s/^more[.]/<more \/>/igm;

    return $formattedcontent;
}

sub create_blog_tag_list {
    my $str = shift;   # pipe-delimited string of tag names created in blog posts with either pound sign (#hashtag) or tag= command.

    # abnormally-delimited string because tag is surrounded by a single verticle bar or pipe like this:
    # |tagone|tagtwo|tagthree|
    # so array elements 1,2, and 3 contain tags
       
    my $html;
 
    my @tags = split(/\|/, $str);
    foreach (@tags) {
        my $tag = $_;
        if ( length($tag) > 1 ) {
            $html .= " #$tag ";
        }
    }
    $html = hashtag_to_link($html);
    return $html;
}

# hashtag suport sub
sub create_tag_list_str {
    my $str = shift; # using the markup code content

    my $tag_list_str = "";
    return $tag_list_str if Utils::get_power_command_on_off_setting_for("code", $str, 0);

    $str = " " . $str . " "; # hack to make regex work
    my @tags = ();
   if ( (@tags = $str =~ m|\s#(\w+)|gsi) ) {
        $tag_list_str = "|";
            foreach (@tags) {
               my $tmp_tag = $_;
               next if  StrNumUtils::is_numeric($tmp_tag); 
               if ( $tag_list_str !~ m|$tmp_tag| ) {
                   $tag_list_str .= "$tmp_tag|";
               }
           }
    }
    return $tag_list_str;
}

sub format_content {
    my $formattedcontent = shift;
    my $markup_type      = shift;

#    my $textile_formatting = 0;
#    $textile_formatting    = 1 if Utils::get_power_command_on_off_setting_for("textile", $formattedcontent, 0); 

    my $newline_to_br = 1;
    if ( !Utils::get_power_command_on_off_setting_for("newline_to_br", $formattedcontent, 1) ) {
        $newline_to_br = 0;
    }

    my $url_to_link = 1;
    if ( !Utils::get_power_command_on_off_setting_for("url_to_link", $formattedcontent, 1) ) {
        $url_to_link = 0;
    }

    $formattedcontent = remove_image_header_commands($formattedcontent); 

    $formattedcontent = remove_power_commands($formattedcontent);

    $formattedcontent = StrNumUtils::trim_spaces($formattedcontent);

    $formattedcontent = process_custom_code_block_encode($formattedcontent);

    $formattedcontent = HTML::Entities::encode($formattedcontent, '<>') if $markup_type eq "textile";

    $formattedcontent = permit_some_html_tags($formattedcontent);

    $formattedcontent = process_embedded_media($formattedcontent);

    $formattedcontent = StrNumUtils::url_to_link($formattedcontent) if $url_to_link;

    $formattedcontent = custom_commands($formattedcontent); 

    $formattedcontent = hashtag_to_link($formattedcontent);

    if ( $markup_type eq "textile" ) {
        $formattedcontent = Textile::textile($formattedcontent);
    } else {
        my $m = Text::MultiMarkdownJRS->new;
        $formattedcontent = $m->markdown($formattedcontent, {newline_to_br => $newline_to_br, heading_ids => 0}  );
    }

    $formattedcontent = process_custom_code_block_decode($formattedcontent);

    $formattedcontent =~ s/&#39;/'/sg;

    $formattedcontent = create_heading_list($formattedcontent);

    return $formattedcontent;
}

sub remove_profile_blog_settings {
    my $str = shift;

    while ( $str =~ m|^blog-description[\s]*=[\s]*(.+)|im ) {
        my $url = $1;
        $str =~ s|^blog-description[\s]*=[\s]*$url||im;
    }

    while ( $str =~ m|^blog-author-image[\s]*=[\s]*(.+)|im ) {
        my $url = $1;
        $str =~ s|^blog-author-image[\s]*=[\s]*$url||im;
    }

    while ( $str =~ m|^blog-banner-image[\s]*=[\s]*(.+)|im ) {
        my $url = $1;
        $str =~ s|^blog-banner-image[\s]*=[\s]*$url||im;
    }

    return $str;
}

sub remove_image_header_commands {
    my $str = shift;
    while ( $str =~ m|^imageheader[\s]*=[\s]*(.+)|im ) {
        my $url = $1;
        $str =~ s|^imageheader[\s]*=[\s]*$url||im;
    }
    while ( $str =~ m|^largeimageheader[\s]*=[\s]*(.+)|im ) {
        my $url = $1;
        $str =~ s|^largeimageheader[\s]*=[\s]*$url||im;
    }
    return $str;
}

sub remove_power_commands {
    my $str = shift;

    # commands must begin at beginning of line
    #
    # toc=yes|no    (table of contents for the article)
    # draft=yes|no
    # code=yes|no
    # webmention=yes|no
    # newline_to_br=yes|no
    # url_to_link=yes|no
    # textile=yes|no
    # block_id=
    # more_text=yes|no

    $str =~ s|^toc[\s]*=[\s]*[noNOyesYES]+||mig;
    $str =~ s|^draft[\s]*=[\s]*[noNOyesYES]+||mig;
    $str =~ s|^code[\s]*=[\s]*[noNOyesYES]+||mig;
    $str =~ s|^webmention[\s]*=[\s]*[noNOyesYES]+||mig;
    $str =~ s|^newline_to_br[\s]*=[\s]*[noNOyesYES]+||mig;
    $str =~ s|^url_to_link[\s]*=[\s]*[noNOyesYES]+||mig;
    $str =~ s|^textile[\s]*=[\s]*[noNOyesYES]+||mig;
    $str =~ s|^block_id[\s]*=[\s]*[\d]+||mig;
    $str =~ s|^more_text[\s]*=[\s]*[noNOyesYES]+||mig;

    return $str;
}

sub process_embedded_media {
    my $str = shift;

    my $cmd = "";
    my $url = "";

    while ( $str =~ m|^(gmap[\s]*=[\s]*)(.*?)$|mi ) {
        $cmd=$1;
#        $url=qq(trim_spaces($2));
        $url= StrNumUtils::trim_spaces($2);
        my $iframe = qq(<iframe width="400" height="300" frameborder="0" scrolling="no" marginheight="0" marginwidth="0" src="http://maps.google.com/$url"></iframe>);
        $str =~ s|\Q$cmd$url|$iframe|;    
    }

    while ( $str =~ m|^(kickstarter[\s]*=[\s]*)(.*?)$|mi ) {
        $cmd=$1;
        $url= StrNumUtils::trim_spaces($2);
        my $iframe = qq(<iframe width="480" height="360" frameborder="0" src="http://www.kickstarter.com/$url"></iframe>);
        $str =~ s|\Q$cmd$url|$iframe|;    
    }

    while ( $str =~ m|^(facebook[\s]*=[\s]*)(.*?)$|mi ) {
        $cmd=$1;
        $url= StrNumUtils::trim_spaces($2);
        my $iframe = qq(<iframe width="640" height="480" frameborder="0" src="http://www.facebook.com/$url"></iframe>);
        $str =~ s|\Q$cmd$url|$iframe|;    
   }

    while ( $str =~ m|^(youtube[\s]*=[\s]*)(.*?)$|mi ) {
        $cmd=$1;
        $url= StrNumUtils::trim_spaces($2);
        my $iframe = qq(<iframe width="480" height="360" frameborder="0" allowfullscreen src="http://www.youtube.com/embed/$url"></iframe>);
        $str =~ s|\Q$cmd$url|$iframe|;    
    }

    while ( $str =~ m|^(vimeo[\s]*=[\s]*)(.*?)$|mi ) {
        $cmd=$1;
        $url= StrNumUtils::trim_spaces($2);
        my $iframe = qq(<iframe src="http://player.vimeo.com/video/$url" width="400" height="300" frameborder="1" webkitAllowFullScreen mozallowfullscreen allowFullScreen></iframe>);
        $str =~ s|\Q$cmd$url|$iframe|;    
    }

    while ( $str =~ m|^(gist[\s]*=[\s]*)(.*?)$|mi ) {
        $cmd=$1;
        $url= StrNumUtils::trim_spaces($2);
        my $gscript = qq(<script src="https://gist.github.com/$url"></script>);
        $str =~ s|\Q$cmd$url|$gscript|;    
    }

    while ( $str =~ m|^(calc[\s]*=[\s]*)(.*?)$|mi ) {
        my $cmd=$1;
        my $arith = $2;
        my $result = eval($arith);
        unless ( $result ) {
            $result = "arithmetic string could not be processed. $@";
        }        
        # $str =~ s|\Q$cmd$arith|[calc] $arith = $result|;    
        $str =~ s|\Q$cmd$arith|$arith = $result|;    
    }

    while ( $str =~ m|^(insta[\s]*=[\s]*)(.*?)$|mi ) {
        $cmd=$1;
        $url        = StrNumUtils::trim_spaces($2);

        my $width  = 320;
        my $height = 320;
        my $insta;
        my @parts = split(/\s+/, $url);
        # $#parts returns the last element number of the array. if two elements, then the number one is returned.
        if ( $#parts ) { 
            my @size = split(/[xX]/, $parts[1]);
            if ( $#size ) {
                $width  = $size[0];
                $height = $size[1];
                my $img_url = _get_instagram_image_url($parts[0]);
                $insta = qq(<img src="$img_url" width="$width" height="$height"></img>);
            }
           
        } else {
            my $img_url = _get_instagram_image_url($url);
            $insta = qq(<img src="$img_url" width="$width" height="$height"></img>);
        }

        $str =~ s|\Q$cmd$url|$insta|;    
    }

    return $str;
}
# embedding media
#
# you tube video: - use url from the youtube embed code in the command
# url to page:              http://www.youtube.com/watch?v=nfOUn6LgN3c
# command to embed:         youtube=nfOUn6LgN3c
#
# facebook video: - grab url to use with command from the embed or share at the facebook page
# url to video:      http://www.facebook.com/video/embed?video_id=10152670330945433
# command to embed: facebook=10152670330945433
#
# google map: - grab url from the link command
# url to map:        http://maps.google.com/maps/ms?msa=0&msid=115189530534020686385.000458eaca4e382f6e81b&cd=2&hl=en&ie=UTF8&ll=41.655824,-83.53858&spn=0.021611,0.032959&z=15 
# command to embed:  gmap=maps/ms?msa=0&msid=115189530534020686385.000458eaca4e382f6e81b&cd=2&hl=en&ie=UTF8&ll=41.648656,-83.538566&spn=0.017445,0.004533&output=embed
#
# kickstarter video: - grab url to use with the command from the embed code
# url to video page:   http://www.kickstarter.com/projects/lanceroper/actual-coffee-a-toledo-coffee-roaster
# command to embed:    kickstarter=lanceroper/actual-coffee-a-toledo-coffee-roaster/widget/video.html
#
# vimeo:
# url to video page:  http://vimeo.com/8578344
# command to embed:   vimeo=8578344


sub process_custom_code_block_encode {
    my $str = shift;

    # code. and code.. custom block

    while ( $str =~ m/(.*?)code\.(.*?)code\.\.(.*)/is ) {
        my $start = $1;
        my $code  = $2;
        my $end   = $3;
        $code =~ s/</\[lt;/gs;
        $code =~ s/>/gt;\]/gs;
        $str = $start . "ccooddee." . $code . "ccooddee.." . $end;
    } 
    $str =~ s/ccooddee/code/igs;
 
    return $str;
}

sub process_custom_code_block_decode {
    my $str = shift;

    $str =~ s/\[lt;/&lt;/gs;
    $str =~ s/gt;\]/&gt;/gs;

    return $str;
}

sub create_heading_list {
    my $str = shift;

    my @headers = ();
    my $header_list = "";

    if ( @headers = $str =~ m{<h([1-6]).*?>(.*?)</h[1-6]>}igs ) {
        my $len = @headers;
        for (my $i=0; $i<$len; $i+=2) { 
            my $heading_text = StrNumUtils::remove_html($headers[$i+1]); 
            my $heading_url  = clean_title($heading_text);
            my $oldstr = "<h$headers[$i]>$headers[$i+1]</h$headers[$i]>";
#            my $newstr = "<a name=\"$heading_url\"></a>\n<h$headers[$i]>$headers[$i+1]</h$headers[$i]>";

            my $newstr = "<a name=\"$heading_url\"></a>\n<h$headers[$i] class=\"headingtext\"><a href=\"#$heading_url\">$headers[$i+1]</a></h$headers[$i]>";

            $str =~ s/\Q$oldstr/$newstr/i;
            $header_list .= "<!-- header:$headers[$i]:$heading_text -->\n";   
        } 
    }

    $str .= "\n$header_list";  
    return $str; 
}

sub _get_instagram_image_url {
    my $source_url = shift;

    my $img_url = "";

    my $source_content = get($source_url);
 
    my $p = HTML::TokeParser->new(\$source_content);

    # my $d = $p->get_tag('meta');
    # $d->[1]{name});  == author
    # $d->[1]{content}); == barney
    # Data Dumper: VAR1 = [ 'meta', { '/' => '/', 'content' => 'barney', 'name' => 'author' }, [ 'name', 'content', '/' ], '' ];

    while ( my $meta_tag = $p->get_tag('meta') ) {
        if ( $meta_tag->[1]{property} eq "og:image" ) {
            $img_url = $meta_tag->[1]{content}; 
        }
    }

    return $img_url;
}

sub get_block_id {
    my $str = shift;

    my $block_id = 0;
    
    if ( $str =~ m|^(block_id[\s]*=[\s]*)(.*?)$|mi ) {
        my $tmp_num = StrNumUtils::trim_spaces($2);
        $block_id = $tmp_num if StrNumUtils::is_numeric($tmp_num); 
    }
    return $block_id;
}

1;

