#!/usr/bin/env perl
# ~* coding: utf-8 *~
#===============================================================================
#
#           FILE: Indexer.pm 
#        AUTHORS: Bianca Ciobanica et Hind Abouabdellah
#
#	         EMAIL: bianca.ciobanica@student.uclouvain.be
#	                hind.abouabdellah@student.uclouvain.be
#           BUGS: 
#          NOTES: Pour l'instant la partie parse travaille sur le chemin direct
#                 Normalement, en lui passant la fonction "extraction", il le
#                 retrouve direct
#
#        VERSION: 5.34
#        CREATED: 21-05-2023 
#
#   DEPENDENCIES: Archive::Zip, File::Basename, File::Spec, FindBin, libreoffice
#===============================================================================
#    DESCRIPTION: Flow :  1) launch_index() starts the whole process
#                 2) then the user's index database is retrieved with
#                 loadindex() or created if None
#                 3) Then we go through user's rep of file_uploads and retrieve all
#                 files using get_files()
#                 4) We then create the indexer with all the pieces using index()
#                 The reversed indexer is a complex hash
#                 5) save the index as .db with sotrable 
#    
#          USAGE: launch_index in project_page.pl (mojo app)
#
#   DEPENDENCIES: File::Basename, File::Spec::Functions, Data::Dump, Storable
#                 PptToPptx, FindBin, Extraction, ParseXml
#===============================================================================
package Indexer;
use strict;
use warnings;

use Exporter qw(import);
our @EXPORT = qw(launch_index);

use lib '../lib';
use File::Spec::Functions qw(catdir catfile);
use Data::Dump qw(dump);
use File::Basename qw(basename);
use Storable qw (dclone store);
use PptToPptx qw(ppt_to_pptx);
use FindBin qw($RealBin);
use utf8;


use Extraction qw(extract_pptx);
use ParseXml qw(parse_file);

my %processed_files;

sub launch_index{
# get dir from user and username
my ($working_dir,$user_rep, $user) = @_;

#create index if file does not exist, if it does, retrieve current user's index and update it
my $index = loadindex($user);
#go through the dir of saved files from user
my @files = get_files($user_rep);

indexer($working_dir,$user_rep, \@files, $user, $index);
# after process terminated save indexer
save_indexer($user, $index, $working_dir);
};

#~~~~~~~ load indexer ~~~~~~~
sub loadindex{
  my ($user) = shift;
  my $filename = $user . '_pptx_indexer.db';
  my $db_path = catdir('..', 'indexerdb');
  my $indexer_file = catfile($db_path, $filename);

  if (-e $indexer_file) { #check if datbase indexer exists
    return retrieve($indexer_file);

  } else { return {}};
};

#~~~~~~~ get files ~~~~~~~
sub get_files{
  my ($data_rep) = shift;
#open dir of user where he uploaded files
  opendir (my $dir, $data_rep) or die ("Failed reading $data_rep\n");
  my @files = readdir($dir);
  closedir $dir;
  return @files;
}

# ~~~~~~~ process files and create indexer ~~~~~~
sub indexer {
  my ($working_dir, $user_rep, $files, $user, $index) = @_;

foreach my $file (@$files){
  if ($file !~ /\.pptx?$/){next;};
  #we cant process the same file!!!!
    next if $processed_files{$file};
    if ($file =~ /\.ppt$/){
      # filename has a path in it
      my $ppt_file = $file;

      # convert .ppt to .pptx using libreoffice
      $file = ppt_to_pptx($ppt_file, $user_rep); 
      
    }
   # EXTRACT 
    print "Extracting ". $file." in process...\n";
    #create dir for user and decompressed data
    my $user_xml_dir =  catdir($working_dir,"decompressed_data", $user, "$file"."_decompressed"); 
    mkdir $user_xml_dir unless -d $user_xml_dir;

eval {
    extract_pptx(catfile($user_rep,$file), $user_xml_dir);
};

if ($@) {
  # An error occurred
  print "Error: $@\n";
  # Additional error handling code or logging can be added here
}

   # PARSE XML
    my $ppt_dir = catdir($user_xml_dir, 'ppt');
    my $ref_data = parse_file($ppt_dir,$file);

    update_indexer($index, $file, $ref_data);
    $processed_files{$file} = 1;
  }
};

# ~~~~~~~ retrieve data from ppt ~~~~~~
sub update_indexer {

my ($index, $file, $ref_data) = @_;

  foreach my $slide_number (keys %{$ref_data->{slides}}) {
    my $slide = $ref_data->{slides}->{$slide_number};

    foreach my $text (@{$slide->{text}}) {
      utf8::decode($text);
		#replace french apostrophe with '
		  $text =~ s/\x{2019}/'/g;
		  my @words = split /\s+|\(|\)|[?;,.!]+\s*|(?<=')/, $text;

      foreach my $word (@words) {
        next if $word eq "";
        utf8::encode($word);

       if (exists $index->{lc $word}{$file}) {
          $index->{lc $word}{$file}{count}++;
        } else {
          # Add the new word to the index for the file
          $index->{lc $word}{$file}{count} = 1;
          $index->{lc $word}{$file}{slides} = {};
        }
        $index->{lc $word}{$file}{slides}{$slide_number} = dclone($slide);
     }
   }
  }
};

sub save_indexer {
  my ($user, $index, $working_dir) = @_;
  print dump ($index);

#generate filename from username
  my $filename = $user. '_pptx_indexer.db';
# database path for each user
  my $db_path = catdir($working_dir,'indexdb');

#store the db / new or updated
  store($index, catfile($db_path, $filename));
};

1;
