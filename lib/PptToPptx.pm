#!/usr/bin/env perl
# ~* coding: utf-8 *~
#===============================================================================
#
#           FILE: PptToPptx.pm 
#        AUTHORS: Bianca Ciobanica et Hind Abouabdellah
#
#	         EMAIL: bianca.ciobanica@student.uclouvain.be
#	                hind.abouabdellah@student.uclouvain.be
#
#           BUGS: 
#          NOTES: il faudrait peut-être ouvrir le fichier log en main.pl 
#        VERSION: 5.34
#        CREATED: 21-05-2023 
#
#===============================================================================
#    DESCRIPTION: Takes a .ppt file and converts it using libreoffice in command
#                 line
#    
#          USAGE: this module is used in Indexer.db to convert ppt to pptx 
#             
#   DEPENDENCIES:  File::Spec::Functions libreoffice 
#===============================================================================
use strict;
use warnings;

package PptToPptx;
use File::Spec::Functions qw(catdir catfile);
use Exporter qw(import);

our @EXPORT = qw(ppt_to_pptx);


sub ppt_to_pptx{

  my ($file, $path) = @_;

  # assign the captured value to filename
  $file =~ /^(.+)\.[^.]+$/;
  my $filename = $1;

  # we can convert the .ppt to .pptx to do the extraction
  my $file_path = catfile ($path, $file);
  my $command = "libreoffice --headless --convert-to pptx --outdir $path $file_path 2> /dev/null";
  system($command);

  #print "Command: $command\n";

  return catfile($filename.".pptx");
}
1;
