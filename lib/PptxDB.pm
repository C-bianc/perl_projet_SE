#!/usr/bin/env perl
# ~* coding: utf-8 *~
#===============================================================================
#
#           FILE: PptxDB.pm 
#        AUTHORS: Bianca Ciobanica et Hind Abouabdellah
#
#	         EMAIL: bianca.ciobanica@student.uclouvain.be
#	                hind.abouabdellah@student.uclouvain.be
#

#           BUGS: 
#          NOTES:  
#        VERSION: 5.34
#        CREATED: 15-06-2023 
#
#===============================================================================
#    DESCRIPTION: Can perform query into the index database (per user)
#                 Can retrieve content for the requested file
#                 Can write to file the results from the search
#                 We always need the working dir (which is the path of 
#                 project_page.pl so main path) and the user name
#    
#          USAGE: functions are called in project_page.pl 
#
#   DEPENDENCIES: Storable, Data::Dump, Data::Dumper, File::Spec::Functions 
#===============================================================================
package PptxDB;
use Storable;
use Data::Dump qw(dump);
use Exporter qw(import);
use File::Spec::Functions qw(catdir catfile);

use Data::Dumper;

our @EXPORT = qw(search write_results get_content);


sub search {
    my ($query, $user, $working_dir) = @_;
    # open database dir
    my $dir = catdir($working_dir,'indexdb');

    # get dir with storable
    my %index = %{ retrieve(catfile($dir, $user.'_pptx_indexer.db')) };

    $query = lc $query;
    my %results;

    # check if request exists
    if ( exists $index{$query} ) {
      print ("EXISTS : $query\n");

    #sort files by their count value in descending order to show files by their relevance
    my @sorted_files = sort { $index{$query}{$b}{count} <=> $index{$query}{$a}{count} } keys %{ $index{$query} };      

    # store for each file, the slide numbers in a list and the numbers are also ordered
    foreach my $file (@sorted_files) {
      $results{$file} = [sort { $a <=> $b } keys %{ $index{$query}{$file}{slides}}];
    } 

    print dump(%results);
    return \%results;
   }
    else {
      #word not found, return False
     return {};
   }
};

sub write_results{
  # write results either of
  my ($user, $wd, $content) = @_;

  # get user path to store results
  my $user_path = $wd."/users/$user";
  my $output_file;
  mkdir $user_path unless -d $user_path;

  $output_file = "$user_path/search_results.txt";
  open(my $fh, '>', $output_file) or die "Could not open file: $!";
  
  foreach my $file (keys %$content) {
    my $slides = join(', ', @{$content->{$file}});
    print $fh "File   : $file\n";
    print $fh "Slides : $slides\n";
    print $fh "\n";
  };
  close $fh;
  return $output_file;
 
};

sub get_content{
# returns a hash with the content of each file
  my ($user,$query, $wd, $file) = @_;
  my $dir = catdir($wd,'indexdb');

  #get index of user's database
  my $userfile = $user.'_pptx_indexer.db';
  my %index = %{ retrieve(catfile($dir, $userfile)) };
  $query = lc $query;

  #results is a hash with files as key and values a list of slide numbers
  # we go through our index to retrieve information about each slide of files

  my $file_content = summarize_file(\%index,$query,$file);
  print dump($file_content);
  return $file_content;

};

sub summarize_file {
  my ($ref_index, $query, $file) = @_;
  my %summary;
  my %index = %$ref_index;
  #print dump(%index);

  my @slides_ordered = sort { $a <=> $b } keys %{$index{$query}{$file}{slides}};
  #extract every titles in file
  my @titles = map { $_->{title} } values %{$index{$query}{$file}{slides}};
  
  foreach $slide (@slides_ordered){
    #each slide has another hash with contains all the info
    my %slide_content = %{$index{$query}{$file}{slides}{$slide}};

       # go through each slide content
    my @title_list =  @{$slide_content{title}};
    # (title, subtitle)
    my $title = $title_list[0];
    if ($title_list[1]) { my $subtitle = $title_list[1]};

    foreach my $text (@{$slide_content{text}}) {
    next if grep { $_ eq $text } @titles;
    #do not add text twice
      if ($subtitle){
        push @{$summary{$title}{subtitle}{$subtitle}{text}}, $text unless grep { $_ eq $text } @{$summary{$title}{subtitle}{$subtitle}{text}};
      }
      else {
        push @{$summary{$title}{text}}, $text unless grep { $_ eq $text } @{$summary{$title}{text}};
      }
    }
    
    #if there are images
    if (@{$slide_content{img}}){
     $summary{$title}{img} = $slide_content{img};
    }
    #if there are hyperlinks
    if (@{$slide_content{hyperlinks}}){
      if ($subtitle){ 
        push @{$summary{$title}{$subtitle}{links}}, $_ foreach @{$slide_content{hyperlinks}};}
      else{ 
        push @{$summary{$title}{links}}, $_ foreach @{$slide_content{hyperlinks}};}
    }
   }
  return \%summary; 
};

1;


