#!/usr/bin/env perl
# ~* coding: utf-8 *~
#===============================================================================
#
#           FILE: project_page.pl 
#        AUTHORS: Bianca Ciobanica et Hind Abouabdellah
#
#	         EMAIL: bianca.ciobanica@student.uclouvain.be
#	                hind.abouabdellah@student.uclouvain.be
#
#           BUGS: bug : retraite les fichiers si lettres accentuees presentes
#          NOTES: 
#        VERSION: 5.34
#        CREATED: 16-06-2023 
#
#===============================================================================
#    DESCRIPTION: The code runs the mojo app website. It uses the plugin 
#                 'Session' and 'RenderFile'. The user can upload up to 500 MB
#                 and the files are processed with Indexer.pm. The search is
#                 done with PptxDB.pm which returns the results of the query
#                 in a hash.
#    
#          USAGE: morbo project_page.pl 
#
#   DEPENDENCIES: Mojo::Upload, JSON, File::Slurp, Mojo::Util, Data::Dumper,
#                 File::Basename, File::Spec::Functions, FindBin, File::Path
#                 Mojolicious::Plugin::Session, PptxDB, Indexer
#===============================================================================
use strict;
use warnings;
use Mojolicious::Lite -signatures;
use Mojo::Upload; 
use Mojolicious::Plugin::Session; # COOKIES
use JSON qw (encode_json decode_json); #to store user data
use File::Slurp qw (read_file write_file); #manipulate files ez
use Mojo::Util 'html_unescape'; #for mojo template
use FindBin qw($RealBin); #for relative path of the main script
use Data::Dumper;
use File::Path qw(remove_tree); #to remove dirs


$ENV{MOJO_MAX_MESSAGE_SIZE} = 500 * 1024 * 1024;
plugin 'RenderFile';
plugin 'Session';

app->sessions->cookie_name('myproject_session');
use lib './lib';
use PptxDB qw (search get_content write_results);
use Indexer qw(launch_index);

my $working_dir = $RealBin;
my $cookie_dir = $working_dir . "/users/users.json";
my $cookie_eaters = $cookie_dir;

my %users;
#allows file data conversion to perl data structure
my $jeeyson_d = read_file($cookie_eaters);

if (-e $cookie_eaters){
   %users =%{decode_json($jeeyson_d)};
} else{
  %users = ();
}

#GET / MAIN PAGE
get '/' => sub {
  my $c = shift;
# || primes over value on right and if left is true then right is not evaluated
  my $registered = $c->param('registered') || 0;
  $c->render(template => '/', registered => $registered);
};

# POST /
post '/' => sub {
    my $c = shift;
    my $username = $c->param('username');
    my $pw = $c->param('pw');
    
    if ($c->param('new_acc')){
      if (exists $users{$username}){
        $c->render(text=> 'Username already exists. Go back to <a href="/"> main page </a>.');return;}
      else {
        #create user, simple hash handling
        $users{$username} = $pw;

        #register users in json
        my $jeeyson_updated = encode_json(\%users);
    write_file($cookie_eaters, $jeeyson_updated);

        #create our COOKIE in mojo
        $c->session(username=> $username);
        #on redirige l'user vers la main page avec la valeur TRUE s'il est enregistré 
        $c->redirect_to('/?registered=1');
        return;}
     };
    #checj if user is in our db
    if (exists $users{$username}) {
        if ($pw eq $users{$username}) {
    #check his pw
          $c->session(username => $username);
          $c->redirect_to('/welcome');
        } else{
          $c->render(text => 'Username or password incorrect. Go back to <a href="/"> main page </a>.');
          }
    } else {
       $c->render(text => 'Unknown user. Please create an account. Go back to <a href="/"> main page </a>.');
    }
 };

# PAGE FOR NAVIGATION
get '/welcome' => sub{
  my $c = shift;
  my $username = $c->session('username');
  $c->render('welcome', username => $username);
}; # this should render when session is active


get '/uploading' => sub { 
  my $c = shift;
  $c->render('uploading');
};

# POST add file
post '/process_files' => sub{
  my $c = shift;
  my $choice = $c->param('action');

  my @uploads = @{$c->req->uploads('files')};
  
   #this list will store the filenames to render them on a list
  my @uploaded_files;  
  my $username = $c->session('username');

   my $user_dir = "$working_dir"."/file_uploads/$username";
   mkdir $user_dir unless -d $user_dir; #-d checks if dir exists
   
#retrieve uploads from submitting form
  #go through uploaded files
   foreach my $upload (@uploads) {
    my $filename = $upload->filename;

    #check if file exists
    if (-e $user_dir."/$filename"){
      $c->render(text => "Cannot add $filename. It already exists. Go back to <a href=\"/uploading\"> submit form </a>". 
      "or to <a href=\"/welcome\"> homepage </a>");
      return;}
    if ($filename =~ /\.pptx?$/) {
      $filename =~ s/\s+/\_/g;
      $upload->move_to("$user_dir/$filename");
      push @uploaded_files, $filename;

    } else {
      $c->render(text => "Error: Could not process $filename. \n
      Invalid file type. Only .pptx or .ppt files are allowed.\n
      Go back to <a href=\"/uploading\"> submit form </a> ");
     # $c->redirect_to('/uploading');
      return;
      }
   };
   # If saving succesful, launch index which will process data
   launch_index($working_dir,$user_dir, $username);
   $c->render('uploading', files => \@uploaded_files);
} => 'save';

get '/index' => sub {
  my $c = shift;
  $c->render('template' => 'index');
};

# POST index
post '/index' => sub {
  my $c = shift;
  my $request = $c->param( 'request' );
  my $user = $c->session('username');
  #create a db per user
  my $dbuser = $user."_pptx_indexer.db";

  # check if exists
  if ( -e "$working_dir/indexdb/$dbuser"){

  my $ref_results = search($request, $user, $working_dir);
  my %results_copy = %$ref_results; 
  $c->session('results'=> \%results_copy);

  $c->stash(request => $request, results => \%results_copy);
  $c->render( 'template' => 'index', request => $request, results => \%results_copy);
  #if empty, cannot do the search
  } else {
    $c->render(text=>"Empty database. Please upload a file <a href=\"/uploading\">here</a> to do a search.");
    return;
}
};

post '/downloadresults' => sub {
  my $c = shift;
  my $request = $c->param('request');
  my $user = $c->session('username');

  #restore results from session
  my $results = $c->session('results');
  my $file = $c->param('file');
  
  # call function from PptxDB to write results
  # the $type argument is just a detail for the filename
  my $output_file = write_results($user, $working_dir, $results);

  # give saving dialog to user 
  $c->render_file(filepath=>$output_file, filename=> "results_$request.txt", content_disposition=>'attachment');
};


#GET summary
get '/preview' => sub {
  my $c = shift;
  my $request = $c->param('request');

  my $user = $c->session('username');
  my $file = $c->param('file');

  my $content;
   # get_content gives a hash with data in it for the file
    $content = get_content($user,$request, $working_dir, $file);

    $c->stash(request => $request, content => $content, file => $file);
    $c->render(template => 'preview', request => $request); 
};

get '/logout' => sub {
  my $c = shift;
# NO MORE COOKIE :-(
  $c->session(expires => 1);
#end cookie tracker
  $c->redirect_to('/');
};

post '/deleteacc' => sub {
  my $c = shift;
 my $user = $c->session('username');

  #reps to remove associated to user
  remove_tree("./file_uploads/$user");
  remove_tree("./decompressed_data/$user");
  my $userdb = $user."_pptx_indexer.db";

#remove database
# risky 
  system("rm -f ./indexdb/$userdb");

#update json data accounts
  delete $users{$user}; #delete user from session

  #store the hash in jeeyson
  my $updated_json_content = encode_json(\%users);
  open my $fh, '>', $cookie_eaters or die "Failed to open file: $!";
  print $fh $updated_json_content;
  close $fh;

  #user begone
  $c->render(text => "Account deleted successfully.");
  $c->redirect_to('/');
};

app->start();

# Knowing how to import a template instead of typing everything here would have been less of an eyesore 

__DATA__
@@ /.html.ep
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
    <title>Ma page</title>
    <style>
        body {
            font-family: helvetica;
            margin: 0;
            padding: 0;
            background-color: #e1f3ff; /* Couleur de fond bleu clair */
        }
        .header {
            background-color: #c2e2f9; /* Couleur de fond du haut de la page */
            padding: 20px;
            text-align: center;
        }
        .logo {
            width: 250px;
            height: auto;
        }
        .content {
            padding: 20px;
            text-align: center;
        }

        .frame {
            border: 2px solid #b2d9f1; /* Couleur de bordure du cadre */
            border-radius: 10px;
            box-shadow: 0 0 5px rgba(0, 0, 0, 0.3);
            padding: 20px;
            background-color: #fff; /* Couleur de fond du cadre */
        }
    .footer {
      background-color: #c2e2f9;
 
      padding: 10px;
      text-align: center;
      font-size: 12px;
      color: #777;
    }
        form {
            margin-top: 20px;
            text-align: center;
        }
        label {
            display: block;
            margin-bottom: 5px;
        }
        input[type="text"],
        input[type="password"] {
            width: 200px;
            padding: 5px;
            margin-bottom: 10px;
        }
        button[type="submit"] {
            padding: 10px 20px;
            background-color: #4CAF50; /* Couleur de fond du bouton */
            color: #fff; /* Couleur du texte du bouton */
            border: none;
            cursor: pointer;
        }
        button[type="submit"]:hover {
            background-color: #45a049; /* Couleur de fond du bouton au survol */
        }
        h2 {
            margin-top: 0;
        }
        h3 {
            margin-top: 20px;
        }
        p {
            margin-bottom: 10px;
        }
    </style>
</head>
  <body>
<div class="header">
        <img src="logoucl.jfif" class="logo" alt="Logo" />
        <h1 style="color: #333;">Welcome to your search engine for PowerPoint slides!</h1>
    </div>
    <div class="content">
        <% if (param 'registered') { %>
        <h2>You can now log in!</h2>
        <% } else { %>
        <h2>Login to your session to upload your files or create a new account!</h2>
        <% } %>

        <form action="/" method="POST">
            <label for="username">Username</label>
            <input type="text" id="username" name="username" required>
            <br><br>
            <label for="pw">Password</label>
            <input type="password" id="pw" name="pw" required>
            <br><br>
            <button type="submit">Login</button>
            <br>
            <p></p>
            <button type="submit" name="new_acc" value="1">Create a new account</button>
        </form>
        <br>
        <div class="frame">
            <h3>Usage</h3>
            <p>You can upload your own .ppt or .pptx files and search through them using a keyword.</p>
            <p>The search engine will show you each file along with the slide numbers where your word was found.</p>
        </div>
    </div>
    <div class="footer">
        <p>About the application<br>
        Future work for a more effective search is ongoing <br>
        Authors: Hind Abouabdellah & Bianca Ciobanica<br>
        LFIAL2630<br>
        &copy; 2022-2023</p>
    </div>
</body>
</html>

@@welcome.html.ep
<!DOCTYPE html>
<html>
  <head>
  <meta charset="utf-8">
  <style>
    body {
      font-family: helvetica;
      margin: 0;
      padding: 0;
      background-color: #e1f3ff; /* Couleur bleu clair */
      text-align: center;
    }
    .header {
      
      background-color: #c2e2f9; /* Couleur de fond du haut de la page */
      padding: 20px;
      text-align: center;
    }
    .logo {
      width: 250px;
      height: auto;
    }
    .content {
      padding: 30px;
      text-align: left;
    }
    .link {
      padding: 35px;
      text-align: left;
    }
    .footer {
     position: fixed;
    left: 0;
    bottom: 0;
    width: 100%;
    background-color: #c2e2f9;
    padding: 10px;
    text-align: center;
    font-size: 12px;
    color: #777;
    }
    button[type="submit"] {
    padding: 10px 20px;
    background-color: #4CAF50; /* Couleur de fond du bouton */
    color: #fff; /* Couleur du texte du bouton */
    border: none;
    cursor: pointer;
}
button[type="submit"]:hover {
    background-color: #45a049; /* Couleur de fond du bouton au survol */
}

  </style>
</head>
  <body>
  <div class="header">
    <img src="logoucl.jfif" class="logo" alt="Logo" />
    <h1>Welcome <%= stash('username') %>!</h1>
  </div>
<div class="content">
    <h2>Use the tabs to navigate</h2>
  </div>
  <div class="link">
    <ul>
      <p><a href="/uploading">Upload your files</a></p>
      <p><a href="/index">Search Engine</a></p>
      <p><a href="/logout">Logout</a></p>
      <br><br><br>
      <form action="/deleteacc" method="POST">
      <button type="submit">Delete account</button>
      </form>
    </ul>
  </div>
  <div class="footer">
    <p>About the application<br>
    Authors: Hind Abouabdellah & Bianca Ciobanica<br>
    LFIAL2630 <br>
    &copy; 2022-2023</p>
  </div>
</body>
</html>

@@ uploading.html.ep
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>
    body {
      font-family: helvetica;
      margin: 0;
      padding: 0;
      background-color: #e1f3ff; /* Couleur de fond bleu clair */
    }
    .header {
      background-color: #c2e2f9;      
      
      padding: 20px;
      text-align: center;
    }
    .logo {
      width: 250px;
      height: auto;
    }
    .content {
      padding: 20px;
      text-align: center;
      align-items: center;
  justify-content: center;
    }
    button[type="submit"] {
            padding: 10px 20px;
            background-color: #4CAF50; /* Couleur de fond du bouton */
            color: #fff; /* Couleur du texte du bouton */
            border: none;
            cursor: pointer;
     }
     button[type="submit"]:hover {
            background-color: #45a049; /* Couleur de fond du bouton au survol */
     }
    .footer {
     position: fixed;
    left: 0;
    bottom: 0;
    width: 100%;
    background-color: #c2e2f9;
    padding: 10px;
    text-align: center;
    font-size: 12px;
    color: #777;
    }
  </style>
</head>
<body>
<div class="header">
    <img src="logoucl.jfif" class="logo" alt="Logo" />
  </div>
  <div class="content">
    <h1>Upload your files here!</h1>
    <p>Only .ppt or .pptx format are supported</p>
    <form action="/process_files" method="POST" enctype="multipart/form-data">
      <p><input type="file" name="files" multiple="multiple"></p>
      <p><button type="submit">Process</button></p>
      <% if (stash('files')) { %>
      <% my $files = stash('files'); %>
      <h3> Upload complete! </h3>
      <h3>Submitted files:</h3>
      <ul>
        <% foreach my $file ( @{$files}) { %>
        <p><%= $file%></p>
        <% } %>
      </ul>
      <% } else { %>
      <p>No files selected.</p>
      <% } %>
    </form>
    <form action="/index" method="POST">
      <button type="submit">Go to Search Engine</button>
    </form>
  </div>
  <div class="footer">
    <p>About the application<br>
    Authors: Hind Abouabdellah & Bianca Ciobanica<br>
    LFIAL2630 <br>
    &copy; 2022-2023</p>
  </div>
</body>
</html>

@@ index.html.ep
<html>
  <head>
    <meta charset="utf-8">
    <title>Search Engine for PowerPoint text</title>
    <style>
    html * {
    font-size: 17px;
  line-height: 1.625;
  color: #2020131;
    }
    body {
      font-family: Arial, sans-serif;
      margin: 0;
      padding: 0;
      background-color: #e1f3ff; /* Couleur de fond bleu clair */
    }
    .header {
      background-color: #c2e2f9;
      padding: 20px;
      text-align: center;
    }
    .logo {
      width: 250px;
      height: auto;
    }
     form {
       margin-top: 10px;
       text-align: center;
       
    }
    .content {
      padding: 10px;
      text-align: center;
    }
    .back{
      position: absolute;
      top: 10px;
      left: 10px;
    }
    .logout-link {
      position: absolute;
      top: 10px;
      right: 10px;
    }
    .button-container {
      margin-top: 10px;
      text-align : left;
    }
    .button-container button {
      display: inline-block;
      vertical-align: middle;
      text-align: center
    }
     button[type="submit"] {
       padding: 5px 10px;
       background-color: #4CAF50; /* Couleur de fond du bouton */
       color: #fff; /* Couleur du texte du bouton */
       border: none;
       cursor: pointer;
       font-size : 14px;
        }
  </style>
  </head>
  <body>
   <div class="header">
    <img src="logoucl.jfif" class="logo" alt="Logo" />
    <h1>Search Engine for PowerPoint text</h1>
  </div>
  <br/>
  <form method="POST" action="/index" enctype="multipart/form-data">
     <h2>Try looking up a keyword &nbsp;:&nbsp;</h2>
     <input type="text" name="request"  size="30" maxlength="80" />
     &nbsp;
     <button type="submit">Search</button>
     
  </form>
  <hr/>
  <% if (my $request = stash('request')) { %>
    <h2>  Results found for&nbsp;<%= $request; %></h2>

    <% my $results = stash('results'); %>
    <p <%= $results %> </p>
    <% if ( defined $results && %$results){ %>
      <div class="button-container">
        <form method="POST" action="/downloadresults">
          <input type="hidden" name="request" value="<%= $request %>">
          <button type="submit">Download Results</button>
        </form>
      </div>
      <ul>
        <% foreach my $file_key (keys %$results) { %>
          <% my @slides = @{ $results->{$file_key} }; %>
          <li>Found in <a href="/preview?request=<%= $request %>&file=<%= $file_key %>"><b><%= $file_key %></b></a>
            <p>Slides: <b><%= join(', ', @slides) %></b></p>
          </li>
        <% } %>
      </ul>
    <% } else { %>
      <p>No results found for <%= $request %></p>
    <% } %>
  <% } %>
<a href="/welcome" class="back">Go back</a> 
<a href="/" class="logout-link">Log out</a>
  </body>
</html>

@@preview.html.ep
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
    <style>
    body {
      font-family: Arial, sans-serif;
      margin: 0;
      padding: 0;
      background-color: #e1f3ff; /* Couleur de fond bleu clair */
    }
    .header {
      background-color: #c2e2f9;
      padding: 20px;
      text-align: center;
    }
    .logo {
      width: 250px;
      height: auto;
    }
    .content {
      padding: 20px;
      text-align: center;
    }
    .logout-link {
      position: absolute;
      top: 10px;
      right: 10px;
    }
    .button-container {
      margin-top: 10px;
    }
    .button-container button {
      display: inline-block;
      vertical-align: middle;
      background-color: green; /* Fond du bouton en vert */
      color: white; /* Couleur du texte en blanc */
      border: none; /* Supprimer la bordure */
      padding: 10px 20px; /* Ajouter un espacement interne au bouton */
      text-align: center; /* Centrer le texte */
      text-decoration: none; /* Supprimer la décoration du texte */
      cursor: pointer; /* Modifier le curseur au survol */
      border-radius: 4px; /* Ajouter des coins arrondis */
    }
  </style>
</head>
<body>
<div class="header">
    <img src="logoucl.jfif" class="logo" alt="Logo" />
    <h2>Summary page for <%= stash('request') %></h2>
  </div>
  <% if (my $content = stash('content')) { %>
    <% for my $title (keys %$content) { %>
    <h2> <%= $title %> </h2>
      <% if (my $subtitle = $content->{$title}{subtitle}) { %>
        <% for my $subtitle_title (keys %$subtitle) { %>
           <% $subtitle_title =~ s/\b($request)\b/<b>$1<\/b>/g ; %>
             <h3> <%== $subtitle_title %> </h3>

          <% if (my $subtitle_text = $subtitle->{$subtitle_title}{text}) { %>
            <% foreach my $line (@$subtitle_text) { %>
              <% $line =~ s/\b($request)\b/<strong>$1<\/strong>/g ; %>
                <p> <%== $line %> </p>
            <% } %>
          <% } %>
          <% if (my $subtitle_links = $subtitle->{$subtitle_title}{links}) { %>
            <% foreach my $link (@$subtitle_links) { %>
              <a href="<%= $link %>">Link</a>
            <% } %>
          <% } %>
        <% } %>
      <% } else { %>
        <% if (my $text = $content->{$title}{text}) { %>
          <% foreach my $line (@$text) { %>
              <% $line =~ s/\b($request)\b/<strong>$1<\/strong>/g ; %>
                <p> <%== $line %> </p>
          <% } %>
        <% } %>
        <% if (my $links = $content->{$title}{links}) { %>
          <% foreach my $link (@$links) { %>
            <a href="<%= $link %>">Link</a>
          <% } %>
        <% } %>
        <% if (my $imgs = $content->{$title}{img}) { %>
          <% foreach my $img (@$imgs) { %>
            <img src="<%= $img %>">
          <% } %>
        <% } %>
      <% } %>
    <% } %>
    <% stash('content',undef); %>
  <% } else { %>
    <p>Failed to render content. Go <a href="/index">back</a></p>
  <% } %>
</body>
</html>

@@ not_found.html.ep
<!DOCTYPE html>
<html>
  <head>
   <meta charset="utf-8">
    <title>Search Engine</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 0;
            background-color: #e1f3ff; /* Couleur bleu clair */
        }
        .header {
            background-color: #c2e2f9;
            padding: 20px;
            text-align: center;
        }
        .logo {
            width: 250px;
            height: auto;
        }
        .content {
            padding: 20px;
            text-align: center;
        }
        .footer {
            background-color: #c2e2f9;
            padding: 10px;
            text-align: center;
            font-size: 12px;
            color: #777;
        }
        h1 {
            color: #555;
        }
        p {
            color: #777;
            margin-bottom: 10px;
        }
        a {
            color: #007bff;
            text-decoration: none;
        }
        a:hover {
            text-decoration: underline;
        }
    </style>
</head>
<body>
    <div class="header">
        <img class="logo" src="logoucl.jfif" alt="Logo">
        <h1>Search Engine</h1>
    </div>
    <div class="content">
        <h1>Oops!</h1>
        <p>The page does not exist.</p>
        <p>Go back to <a href="/">home page</a>.</p>
    </div>
    <div class="footer">
        <p>About the application<br>
        Authors: Hind Abouabdellah & Bianca Ciobanica<br>
        LFIAL2630 <br>
        &copy; 2022-2023</p>
    </div>
  </body>
</html>
