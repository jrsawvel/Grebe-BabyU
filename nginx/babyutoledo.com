########
# GREBE
########

server {
	listen   80; 

	server_name babyutoledo.com;

        location ~ ^/(css/|javascript/|images/) {
          root /home/babyuProd/Grebe/root;
          access_log off;
          expires max;
        }

        location /api/v1 {
	     root /home/babyuProd/Grebe/root/api/v1;
             index grebeapi.pl;
             rewrite  ^/(.*)$ /grebeapi.pl?query=$1 break;
             fastcgi_pass  127.0.0.1:8999;
             fastcgi_index grebeapi.pl;
             fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
             include fastcgi_params;
        }

        set $use_cache 1;
        set $post_id 0;
        if ($http_cookie ~* "babyuProduserid=[1-9]+") {
            set $use_cache 0;
        }
        if ($request_uri ~ "^/([0-9]+)") {
            set $post_id $1;
            set $use_cache "${use_cache}1";
        }
        if ($request_uri ~ "^/$") {
            set $post_id "homepage";
            set $use_cache "${use_cache}1";
        }

        location / {
             # deny 108.73.171.0/24;

             default_type text/html;
             if ( $use_cache = 11 ) {
                 set $memcached_key "babyutoledo.com-$post_id";
                 memcached_pass 127.0.0.1:11215;
             }
             error_page 404 = @fallback;
        }

        location @fallback {
	     root /home/babyuProd/Grebe/root;
             index grebe.pl;
             rewrite  ^/(.*)$ /grebe.pl?query=$1 break;
             fastcgi_pass  127.0.0.1:8999;
             fastcgi_index grebe.pl;
             fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
             include fastcgi_params;
        }
}


