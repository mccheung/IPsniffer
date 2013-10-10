#!/usr/bin/env perl
use Mojolicious::Lite;
use DBI;
use Text::CSV;
use File::Temp qw/ tempfile /;
#use Data::Dumper;
use Mojolicious::Plugin::RenderFile;

my $user = 'root';
my $pass = 'password';

plugin 'RenderFile';

my $countrys;

my $dbh = DBI->connect( 'dbi:mysql:IPsniffer', $user, $pass ) || die "Can't connect to database\n";

get '/' => sub {
  my $self = shift;

  my $sql = qq/select * from ip_data limit 1/;

  my @res = $dbh->selectrow_array( $sql );

  set_stash( $self );
  $self->render('index', recs => \@res );
};

post '/' => sub {
  my $self = shift;

  my $pobj = $self->req->params->to_hash;

  my $search_sql = prepare_sql( $pobj );
  $self->app->log->debug( "SQL: $search_sql\n" );
  set_stash( $self, 1 , $pobj);

  my @recs = $dbh->selectall_arrayref( $search_sql );

  $self->stash( recs => \@recs );
  $self->render( 'query' );
};

post '/csv' => sub {
  my ( $self ) = @_;

  my $pobj = $self->req->params->to_hash;
  my $search_sql = prepare_sql( $pobj, 1 );

  my @recs = $dbh->selectall_arrayref( $search_sql );

  my ($fh, $filename) = tempfile(
    DIR => '/var/tmp',
    TEMPLATE => "Search_by_$pobj->{ search_type }_XXXXXX",
    ULINK=>0,
    SUFFIX => '.CSV'
  );

  print "Fuck File Name: $filename\n";
  my @cols = qw/ip_from ip_to city country_name isp_name mcc mnc mobile_brand/;

  my $csv = out_csv( $fh, \@cols, \@recs, $pobj->{ ip_format }, $pobj->{ search_type } );

  $self->render_file(
    'filepath' => $filename,
    'format'   => 'CSV',
  );

};

# prepare query statement
sub prepare_sql {
  my ( $params, $is_csv ) = @_;
  my $pre_page = $params->{ pre_page } || 100;
  my $search_type = $params->{ 'search_type' };
  my $sql = qq/select ip_from, ip_to, city, country_name, isp_name, mcc, mnc, mobile_brand from ip_data where/;

  #if ( $search_type ne 'mobile' ) {
  #  $sql = qq/select ip_from, ip_to, city, country_name, isp_name, '-', '-', '-' from ip_data where/;
  #}else {
  #  $sql = qq/select ip_from, ip_to, city, country_name, isp_name, mcc, mnc, mobile_brand from ip_data where/;
  #}

  my @country = ref( $params->{ country } ) eq 'ARRAY' ? @{$params->{ country }} : ( $params->{ country });
  foreach ( @country ) {
    s/\'/\\'/g;
  }

  my $tmp_str = join( ' or ', map { "country_name = '$_'" } @country );
  $sql .= '( ' . $tmp_str . ')';

  if ( $params->{ search_type } && $params->{ search_type } eq 'mobile' ) {
    $sql .= ' and ( length( mobile_brand ) > 1';
    $sql .= ' or length( mcc ) > 1';
    $sql .= ' or length( mnc ) > 1 )';
    # if $params->{ mobile } && lc( $params->{ mobile } ) eq 'on';
  }

  if ( $params->{ search_type } && $params->{ search_type } eq 'city' ) {
    my $condition = $params->{ condition };
    my $city = $params->{ city };

    if ( $condition eq 'equals' ) {
      $sql .= ' and city = "' . $city . '"';
    }

    if ( $condition eq 'begin' ) {
      $sql .= ' and city REGEXP "^' . $city . '"';
    }

    if ( $condition eq 'no_begin' ) {
      $sql .= ' and city NOT REGEXP "^' . $city . '"';
    }

    if ( $condition eq 'end' ) {
      $sql .= ' and city REGEXP "' . $city . '$"';
    }

    if ( $condition eq 'no_end' ) {
      $sql .= ' and city NOT REGEXP "' . $city . '$"';
    }

    if ( $condition eq 'contains' ) {
      $sql .= ' and city REGEXP "' . $city . '"';
    }

    if ( $condition eq 'no_contains' ) {
      $sql .= ' and city NOT REGEXP "' . $city . '"';
    }
  }

  # for search by company condition
  if ( $params->{ search_type } && $params->{ search_type } eq 'company' ) {
    my $condition = $params->{ condition };
    my $company = $params->{ company };

    if ( $condition eq 'equals' ) {
      $sql .= ' and isp_name = "' . $company . '"';
    }

    if ( $condition eq 'begin' ) {
      $sql .= ' and isp_name REGEXP "^' . $company . '"';
    }

    if ( $condition eq 'no_begin' ) {
      $sql .= ' and isp_name NOT REGEXP "^' . $company . '"';
    }

    if ( $condition eq 'end' ) {
      $sql .= ' and isp_name REGEXP "' . $company . '$"';
    }

    if ( $condition eq 'no_end' ) {
      $sql .= ' and isp_name NOT REGEXP "' . $company . '$"';
    }

    if ( $condition eq 'contains' ) {
      $sql .= ' and isp_name REGEXP "' . $company . '"';
    }

    if ( $condition eq 'no_contains' ) {
      $sql .= ' and isp_name NOT REGEXP "' . $company . '"';
    }
  }

  # for pages, when build a CSV file, we need return all result
  unless ( $is_csv ) {
    my $page = $params->{ page } || 0;
    my $off_set = $page * $pre_page;
    $sql .= " limit $off_set, $pre_page";
  }

  return $sql;
}

# stash some common variable
sub set_stash {
  my ( $self, $is_post, $pobj ) = @_;

  $is_post = 0 unless $is_post;
  my $countrys = get_country();
  $pobj->{ page } = 0 unless $pobj->{ page };
  $self->stash( pobj => $pobj ) if $pobj;
  $self->stash( countrys => $countrys, is_post => $is_post );
}

sub get_country {
  my $sql = qq/select country_name from ip_data group by country_name/;
  return $countrys if $countrys;
  my $ctys = $dbh->selectall_arrayref( $sql );
  $countrys = $ctys;
  return $countrys;
}


sub convert_ip {
  my ( $number ) = @_;

  my @ip;
  for(my($i) = 0; $i < 4; $i++)
  {
    $ip[$i] = $number % 256;
    $number = ( $number - $ip[$i] ) / 256;
  }
  return "$ip[3].$ip[2].$ip[1].$ip[0]";

}


helper convert_ip => sub {
  my ( $self, $number ) = @_;

  my @ip;
  for(my($i) = 0; $i < 4; $i++)
  {
    $ip[$i] = $number % 256;
    $number = ( $number - $ip[$i] ) / 256;
  }
  return "$ip[3].$ip[2].$ip[1].$ip[0]";
};


sub out_csv {
  my ( $fh, $cols, $data, $format, $search_type ) = @_;

  my $csv = Text::CSV->new(
    {
      binary       => 1,
      eol          => $/,
      sep_char     => ",",
      always_quote => 1,
      quote_space  => 0,
      quote_null   => 1,
    }
  ) || die "Cannot use CSV ";

  if ( $search_type ne 'mobile' ){
    $csv->combine(@$cols[0..4]);
  } else {
    $csv->combine(@$cols);
  }
  print $fh $csv->string();

  #print Dumper( $data );
  foreach my $row (@$data) {
    foreach my $row_s ( @$row ) {
      if ( $format eq 'ip' ) {
        $row_s->[0] = convert_ip( $row_s->[0] );
        $row_s->[1] = convert_ip( $row_s->[1] );
      }
      if ( $search_type ne 'mobile') {
        $csv->combine( @$row_s[0..4] );
      } else {
        $csv->combine( @$row_s[0..7] );
      }
      print $fh $csv->string();
      #print $csv->string();
    }
  }

  return $csv;
}


app->start;


__DATA__

@@ index.html.ep
% layout 'default';
% title 'IPsniffer';
<div class="search_form" style="display:block;float:left;margin-left:15px"><p>Mobile Operator Search</p>
<form method="POST">
  <input type="hidden" name="search_type" value="mobile" />
  <div>
    <div>Country:<span style="float:right" ><input type="button" name="Button" value="Select All" onclick="selectAll('mobile',true)" /></span></div>
    <select name="country" multiple size="10" id="mobile">
      % foreach my $key ( @$countrys ) {
        <option value="<%=$key->[0]%>" selected><%=$key->[0]%></option>
      % }
    </select>
  </div>
  <br />
  <div><span>Results Pre Page:</span>
  <select name="pre_page">
    <option value="100"> 100 </option>
    <option value="300"> 300 </option>
    <option value="500"> 500 </option>
  </select>
  </div>
  <br />
  <input type="submit" display="Search Now" />
</form>
</div>

<div class="search_form" style="display:block;float:left;margin-left:15px"><p>City Search</p>
<form method="POST">
  <input type="hidden" name="search_type" value="city" />
  <div>
    <div>Country:<span style="float:right" ><input type="button" name="Button" value="Select All" onclick="selectAll('city',true)" /></span></div>
    <select name="country" multiple size="10" id="city">
      % foreach my $key ( @$countrys ) {
        <option value="<%=$key->[0]%>" selected><%=$key->[0]%></option>
      % }
    </select>
  </div>
  <br />
  <div><span>City:</span> <input type="text" name="city" /></div>
  <br />
  <div>
    <span>Condition:</span>
    <select name="condition" >
      <option value="equals" selected>Equals</option>
      <option value="begin" >Begins with</option>
      <option value="no_begin" >Does not begin with</option>
      <option value="end" >Ends withEquals</option>
      <option value="no_end" >Does not end with</option>
      <option value="contains" >Contains</option>
      <option value="no_contains" >Does not contain</option>
    </select>
  </div>
  <br />

  <div><span>Results Pre Page:</span>
  <select name="pre_page">
    <option value="100"> 100 </option>
    <option value="300"> 300 </option>
    <option value="500"> 500 </option>
  </select>
  </div>
  <br />
  <input type="submit" display="Search Now" />
</form>
</div>

<div class="search_form" style="display:block;float:left;margin-left:15px"><p>Company Search</p>
<form method="POST">
  <input type="hidden" name="search_type" value="company" />
  <div>
    <div>Country:<span style="float:right" ><input type="button" name="Button" value="Select All" onclick="selectAll('company',true)" /></span></div>
    <select name="country" multiple size="10" id="company">
      % foreach my $key ( @$countrys ) {
        <option value="<%=$key->[0]%>" selected><%=$key->[0]%></option>
      % }
    </select>
  </div>
  <br />
  <div><span>Company:</span> <input type="text" name="company" /></div>
  <br />
  <div>
    <span>Condition:</span>
    <select name="condition" >
      <option value="equals" selected>Equals</option>
      <option value="begin" >Begins with</option>
      <option value="no_begin" >Does not begin with</option>
      <option value="end" >Ends withEquals</option>
      <option value="no_end" >Does not end with</option>
      <option value="contains" >Contains</option>
      <option value="no_contains" >Does not contain</option>
    </select>
  </div>
  <br />

  <div><span>Results Pre Page:</span>
  <select name="pre_page">
    <option value="100"> 100 </option>
    <option value="300"> 300 </option>
    <option value="500"> 500 </option>
  </select>
  </div>
  <br />
  <input type="submit" display="Search Now" />
</form>
</div>


@@ query.html.ep
% layout 'default';
% title 'IPsniffer';

<div>
  <div>
    <a href="/">Back to Search Page</a>
  </div>
  <div style="margin-top:10px;margin-bottom:10px;">
  <form method="POST" action="/csv">
    % foreach my $key ( keys $pobj ) {
      % my $val;
      % if ( ref( $pobj->{ $key } ) eq 'ARRAY' ) {
        <select name="<%= $key %>" multiple style="display:none;">
          % foreach my $val ( @{ $pobj->{ $key } } ) {
          <option value="<%=$val %>" selected><%=$val%></option>
          % }
        </select>
      % } else {
        <input type="hidden" name="<%= $key %>" value="<%= $pobj->{ $key } %>" />
      % }
    % }
    IP format: <input type="radio" name="ip_format" value="ip" checked="checked">Dotted Decimal&nbsp;&nbsp;<input type="radio" name="ip_format" value="number">Numerical
    <br />
    <br />
    <input type="submit" value="Download CSV" />
  </form>
  </div>
</div>

<!-- page bar -->
<div style="clean:both; float:right">
  <span style="float:left">
    <form method="POST">
        % foreach my $key ( keys $pobj ) {
          % next if $key eq 'page';
          % my $val;
          % if ( ref( $pobj->{ $key } ) eq 'ARRAY' ) {
            <select name="<%= $key %>" multiple style="display:none;">
              % foreach my $val ( @{ $pobj->{ $key } } ) {
              <option value="<%=$val %>" selected><%=$val%></option>
              % }
            </select>
          % } else {
            <input type="hidden" name="<%= $key %>" value="<%= $pobj->{ $key } %>" />
          % }
        % }
        <input type="hidden" name="page" value="<%= $pobj->{ page } - 1 %>" />
        <input type="submit" value="<< Pre Page" />
    </form>
  </span>

  <span style="float:left;margin-left:15px;">Current Page: <%= $pobj->{ page } + 1 %>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</span>

  <span style="float:left">
  <form method="POST">
    % foreach my $key ( keys $pobj ) {
      % next if $key eq 'page';
      % my $val;
      % if ( ref( $pobj->{ $key } ) eq 'ARRAY' ) {
        <select name="<%= $key %>" multiple style="display:none;">
          % foreach my $val ( @{ $pobj->{ $key } } ) {
          <option value="<%=$val %>" selected><%=$val%></option>
          % }
        </select>
      % } else {
        <input type="hidden" name="<%= $key %>" value="<%= $pobj->{ $key } %>" />
      % }
    % }
    <input type="hidden" name="page" value="<%= $pobj->{ page } + 1 %>" />
    <input type="submit" value="Next Page >>" />
    </form>
  </span>
</div>
<br>
<h2>Search Results</h2>
<hr/>
<table>
  <thead>
    <tr>
      <th>StartIP</th>
      <th>EndIP</th>
      <th>City</th>
      <th>Country</th>
      <th>Company( ISP )</th>
      % if ( $pobj->{ search_type } eq 'mobile' ) {
      <th>MCC</th>
      <th>MNC</th>
      <th>Mobile Brand</th>
      % }
    </tr>
  </thread>
  <tbody>
  % foreach my $rec ( @$recs ) {
    % foreach my $val ( @$rec ) {
    <tr>
      <td><%= convert_ip( $val->[0] ) %></td>
      <td><%= convert_ip( $val->[1] ) %></td>
      <td><%= $val->[2] %></td>
      <td><%= $val->[3] %></td>
      <td><%= $val->[4] %></td>
      % if ( $pobj->{ search_type } eq 'mobile' ) {
        <td><%= $val->[5] %></td>
        <td><%= $val->[6] %></td>
        <td><%= $val->[7] %></td>
      % }
    </tr>
    % }
  % }
  </tbody>
<table>
<hr />
<br />
<br />


@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head>
    <title><%= title %></title>
    <script typt="text/javascript">
      function selectAll(selectBox,selectAll) {
        // have we been passed an ID
        if (typeof selectBox == "string") {
          selectBox = document.getElementById(selectBox);
        }
        // is the select box a multiple select box?
        if (selectBox.type == "select-multiple") {
          for (var i = 0; i < selectBox.options.length; i++) {
            selectBox.options[i].selected = selectAll;
          }
        }
      }
    </script>
  </head>
  <body><%= content %></body>
</html>


