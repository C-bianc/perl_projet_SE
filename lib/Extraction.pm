#! /usr/bin/env perl
# ~* coding: utf-8 *~
#===============================================================================
#
#           FILE: Extraction.pm
#        AUTHORS: Bianca Ciobanica et Hind Abouabdellah
#	         EMAIL: bianca.ciobanica@student.uclouvain.be
#	                hind.abouabdellah@student.uclouvain.be
#
#           BUGS: 
#          NOTES: change the extraction path to $destination when on web
#        VERSION: 5.34
#        CREATED: 21-05-2023 
#
#===============================================================================
#    DESCRIPTION:  This module takes a .pptx file and the directory it has
#                 to extract in and compresses & decompresses the whole
#                 pptx data in the destination (decompressed_data)
#    
#          USAGE: this module is used in Indexer.pm on each .pptx file
#
#   DEPENDENCIES: Archive::Zip, File::Basename, File::Spec::Functions 
#===============================================================================

package Extraction;
use Exporter qw(import);
use Archive::Zip qw(:ERROR_CODES);
use File::Spec::Functions qw(catdir); # to concatenate dir names
use File::Basename qw(basename); # to get filename


our @EXPORT = qw(extract_pptx);

use warnings;
use strict;

#~~~~~~~~~Extraction~~~~~~~~~


# we will use basename to get only the filename

sub extract_pptx{

  my ($file,$working_dir) = @_;
  
  #convert ppt to pptx

  my $filename = basename($file);

  # create zip file
  my $zip = Archive::Zip->new($file); die "Failed to open file $file. Make sure the format is .pptx\n" unless $zip;

  # extract all the files in the zip to the dest
  $zip->extractTree('', $working_dir); # ($root, $dest)
  return 1;
};



1;
