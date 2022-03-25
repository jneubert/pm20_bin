use Web::Sitemap;
 
my $sm = Web::Sitemap->new(
        output_dir => '/path/for/sitemap',
 
        ### Options ###
 
        temp_dir    => '/path/to/tmp',
        loc_prefix  => 'http://my_domain.com',
        index_name  => 'sitemap',
        file_prefix => 'sitemap.',
 
        # mark for grouping urls
        default_tag => 'my_tag',
 
 
        # add <mobile:mobile/> inside <url>, and appropriate namespace (Google standard)
        mobile      => 1,
 
        # add appropriate namespace (Google standard)
        images      => 1,
 
        # additional namespaces (scalar or array ref) for <urlset>
        namespace   => 'xmlns:some_namespace_name="..."',
 
        # location prefix for files-parts of the sitemap (default is loc_prefix value)
        file_loc_prefix  => 'http://my_domain.com',
 
        # specify data input charset
        charset => 'utf8',
 
        move_from_temp_action => sub {
                my ($temp_file_name, $public_file_name) = @_;
 
                # ...some action...
                #
                # default behavior is
                # File::Copy::move($temp_file_name, $public_file_name);
        }
 
);
 
$sm->add(\@url_list);
 
 
# When adding a new portion of URL, you can specify a label for the file in which these will be URL
 
$sm->add(\@url_list1, tag => 'articles');
$sm->add(\@url_list2, tag => 'users');
 
 
# If in the process of filling the file number of URL's will exceed the limit of 50 000 URL or the file size is larger than 50MB, the file will be rotate
 
$sm->add(\@url_list3, tag => 'articles');
 
 
# After calling finish() method will create an index file, which will link to files with URL's
 
$sm->finish;

