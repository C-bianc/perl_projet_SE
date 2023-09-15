#!/usr/bin/env perl
# ~* coding: utf-8 *~
# CE CODE EST UTILISE POUR VERIFIER SI PPTXDB MARCHE MAIS NE FAIS PAS
#PARTIE DU PROJET

use strict;
use warnings;
use lib './lib';
use PptxDB qw (search get_content);    
use FindBin qw($RealBin);


my $query = $ARGV[0];    
#INSERER LE NOM DU FICHIER ICI
my $file = "LROM1331-B_Seance6bis_les-chevauchementsAUDIO.pptx";
my $type = "file";

my $ref_files = search($query, 'test', "../$RealBin");
my %results = %{$ref_files};
#
foreach my $file ( keys %results){
  my @slides = @{$results{$file}};
  print "found in $file in slides "; 
  print join ', ', @slides; print "\n";
}

get_content ('test', $query, $RealBin, $file, "file");

