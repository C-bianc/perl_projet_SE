#! /usr/bin/env perl
# ~* coding: utf-8 *~
#===============================================================================
#
#           FILE: ParseXml.pm 
#           
#        AUTHORS: Bianca Ciobanica et Hind Abouabdellah
#
#	         EMAIL: bianca.ciobanica@student.uclouvain.be
#	                hind.abouabdellah@student.uclouvain.be
#
#           BUGS: cannot move pictures found in public dir :-( 
#          NOTES: audios in p:pic ?
#                 <a:audioFile r:embed="" r:link="rId1" />
#                 <a:videoFile r:embed="" r:link="rId1" />
#                 pic description ?
#                 language found in each slide ? FAILED
#
#        VERSION: 5.34
#        CREATED: 21-05-2023 
#
#===============================================================================
#    DESCRIPTION: XML::Twig->new() on indique ce que l'on cherche
#                 chaque fonction pour le twig handler a 2 arguments
#                 le $twig et l'élément que l'on recherche $elem
#                 $twig = arbre xml complet (manipulation sur tout l'arbre)
#                 $elem = sous arbre xml (ce que l'on recherche)
#                 le résultat final est une grande hash complexe
#                 chaque numéro de slide est une clé et contient le reste
#                 le titre, texte, images et liens sont stockés dans une liste
#    
#          USAGE: parse_file is called in Indexer.pm for each file 
#
#   DEPENDENCIES: XML:Twig, File::Copy, File::Basename, File::Spec::Functions
#===============================================================================
package ParseXml;
use File::Spec::Functions qw(catdir catfile);
use File::Basename;
use File::Copy qw(move);
use Exporter qw(import);
our @EXPORT = qw(parse_file); 

use strict;
use warnings;
use XML::Twig;
use utf8;

#create hash to store the data
my %data = (
info => {filename=>undef, lang=>undef,},
slides => {},
);

#MY DIR /!\
my $pic_dir = "/home/cbianc/Documents/Cours_M1Q2/Perl/perl_projet/public";

sub parse_file{
  
  #this sub will loop through each xml files to extract the content we want

  my ($working_dir,$pptfile) = @_;
  print "WORKING DIR : $working_dir\n";
  my $slides_dir = catfile($working_dir,"slides","slide*.xml");
  print("SLIDES DIR : $slides_dir\n");

  # go through each xml files
  # glob uses UNIX path style so will have to change this part for windows
    foreach my $file (glob $slides_dir){

      next if $file =~ /^\./;
      next if $file eq '_rels';

      # get index 
      my ($idx) = $file =~ /slide(\d+)/;

      # dont know if this is useful
      $data{info}{filename} = $pptfile;
      $data{info}{lang}= undef;
      $data{slides}{$idx}{text} = [];
      $data{slides}{$idx}{img} = [];
      $data{slides}{$idx}{title} = [];
      $data{slides}{$idx}{hyperlinks} = [];

       #parse 
      my $process = parse_xml($file,$working_dir, $idx);
      if ($process) {print "Parsed content from $file successfully !\n"} else {print "Parsing $file failed\n."};

      # get comments
      my $comment_f = catfile($working_dir,"comments", "comment$idx.xml");
        # if file exists
      if (-e $comment_f){
        my $ref_comments = comments($working_dir,$idx,$comment_f);
        my @comments = @$ref_comments;

        $data{slides}{$idx}{comments} = @comments;
      }
      else {#do nothing
        };

    };
  return \%data;
};

#~~~~~~~~~~Comments~~~~~~~~~~
sub comments{

  # Search for comments that are in ppt/comments/comment*.xml
  my ($working_dir, $idx, $file) = @_;
  my @comments;

  #text is in <p:text> tags
  my $twig = XML::Twig->new(
  twig_handlers => 
  {'p:text' => sub{
    my ($twig, $comment) = @_;
    my $text = $comment->text;
    push @comments, $text;
    }
  }
 );
  $twig->parsefile($file);

  return \@comments;
};

#~~~~~~~~~~Text, Img~~~~~~~~~
sub parse_xml{
  # main sub that parses each slide*.xml file. Returns True if parsing successful, otherwise False
 
  my ($file,$working_dir,$idx) = @_;

  # create twigs for parsing, each twig launches a sub for each type of content
  # each sub stores data in the main hash
  
  # <p:sld> holds every paragraph (main tree)
  # <p:pic> holds a pic
  my $twig = XML::Twig->new(
  twig_handlers => {
    'p:sld' => sub{text($idx,$working_dir, @_)},
    'p:pic' => sub{pic($idx,$working_dir, @_)},
  # normally it should be \&subroutine but we need to pass it arguments 
  # so sub { sub () } is an anonymous code ref
  }
 );

  eval {
    $twig->parsefile($file);
  };

  # success ?
  if ($@) {
      return 0;  # parsing failed
  }
  return 1;  #
}; 

#=======text handler=======
sub text {
  my ($idx,$working_dir,$twig, $line) = @_;

  # .// means any node at any depth recursively
  # findnodes returns a list of object founds

  my @lines = $line->findnodes('.//p:sp'); # paragraphs

  foreach my $node (@lines) {
    my @text = $node->findnodes('.//a:t'); # runs
    #get type (not always present)
    my @types = $node->findnodes('.//p:ph');

    if (@types){
      foreach my $type_elem (@types){
      my $attr = $type_elem->att('type');
      if ($attr) {
      push @{$data{slides}{$idx}{$attr}}, $_->text foreach @text;
        }
      }
    }
    # find text as hyperlinks
    my @hlink_elements = $node->findnodes('.//a:hlinkClick');

    if (@hlink_elements) {
      # if hyperlinks exist
      foreach my $hlink (@hlink_elements){
        my $rel = $hlink->att('r:id');
        my $name = find_name($working_dir, $idx, $rel);
        push @{$data{slides}{$idx}{hyperlinks}}, $name;
      }
    }
    else{
    # push normal text into text array
    push @{$data{slides}{$idx}{text}}, $_->text foreach @text;
    }
  }
};

#=======pic handler=======
sub pic {
  my ($idx,$working_dir,$twig, $pic) = @_;
  

  # maybe add pic descr found in p:pic under:
  # <p:nvPicPr>
  # <p:cNvPr id="4" name="St_Patrick's_Day.jpg"
  # descr="This is a Saint Patrick's day picture"/>

  #$pic = current <p:pic> element
  #where we find the a:blip and retrieve the attribute r:embed to get the id
  my $picid = $pic->get_xpath('.//a:blip', 0);
  if ($picid) {
    my $rel = $picid->att('r:embed');

    my $name = find_name($working_dir,$idx, $rel, 'pic');
    
    push @{$data{slides}{$idx}{img}}, $name;
  }
};

sub find_name{
  # this sub allows to find implicit relations for hyperlinks and images by their ID found in slide*.xml

  my ($working_dir,$idx, $rel, $type) = @_;
  my $target;
  my $relationships_file = catfile($working_dir,"slides","_rels","slide$idx.xml.rels");

  my $twig = XML::Twig->new(
  twig_handlers=>{
    'Relationship' => sub{
      my ($twig, $relationship) = @_;

      # name of object is found with $rel
      # this $rel is found in the .rels file under the 'Id' attribute
      # the name we want is under 'Target' attribute
      if ($relationship->att('Id') eq $rel){
        $target = $relationship->att('Target');
        if ($type eq 'pic'){
        my $filename = basename($target);
        my $target_file = catfile($pic_dir, $filename);
        
        move($target, $target_file);
        $target = $filename;
      }}
    }
  }
  );
  $twig->parsefile($relationships_file);

  return $target;
};


1;  
