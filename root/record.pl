#!/usr/bin/perl

use File::Path ;
use Proc::Background;
use DBI;
use Net::VNC; 
use Config::Tiny;

my $cfg = new Config::Tiny->read('config.ini');

if ($< == 0){
  print "Great, we are root, continuing...\n";
} else {
  print "Please run this script as root!\n";
  exit(0);
}

my $dbh = DBI->connect("DBI:mysql:database=present;host=localhost;port=" . $cfg->{mysql}->{port},$cfg->{mysql}->{username},$cfg->{mysql}->{password}) or die "Unable to connect...\n";
$dbh->do("delete from events");
$dbh->do("delete from active_recording");
print "Default topic: " . $cfg->{record}->{topic_default} . "\n";
print "Default topic will be used for the topic unless you change the value below.\n";
print "Enter topic for the inital podcast: ";
my $topic = <STDIN>;
$topic =~ chomp ($topic);

if (length($topic)==0){
  print "Using default topic...\n";
  $topic = $cfg->{record}->{topic_default};
}

my $epoch = time;

my $data_dir = $cfg->{record}->{data_path} . $epoch;
mkpath $data_dir;
my $sql = qq{INSERT into active_recording(epoch_start) value (?)};
my $sth = $dbh->prepare($sql);
$sth->execute($epoch);
&insertEvent($epoch,"START",$topic);
my $recorder = Proc::Background->new($cfg->{record}->{record_string} . " " . $data_dir ."/audio.wav");
sleep (1);
if ($recorder->alive()){
 print "OK\n";
} else {
  print "There was something wrong with the record string.  Check the value and try again.\n";
  exit (0);
}
system("clear");

while (1==1){
  print "Menu:\n";
  my $sql2=qq{SELECT host_alias,password,ip from vnc_clients where barcode_ok=4 order by client_id};
  my $sth2 = $dbh->prepare($sql2);
  $sth2->execute();
  my $ha;
  my $pw;
  my $ip;
  $sth2->bind_columns(undef,\$ha,\$pw,\$ip);
  my $i = 0;
  my %hash;
  while ($sth2->fetch()){
    $i = $i + 1;
    print "$i : $ha : $ip \n";
    $hash{$i} = $ha . ":" . $ip . ":" . $pw;
  }
  print "S or +: Delay 5 seconds before doing x...\n";
  print "Q: Quit\n";

  print "Selection:";
  my $sel = <STDIN>;
  $sel =~ chomp ($sel);
  if (($sel =~/\+/) || ($sel =~ /S/i)){
    print "Sleeping 5 seconds...\n";
    sleep(5);
    $sel =~ s/\+//g;
    $sel =~ s/S//g;
    $sel =~ s/s//g;
    $sel =~ s/\ //g; # Remove space between commands if any
  }
  if ($sel =~/q/i){
    print "Quiting...\n";
    $recorder->die();
    my $z = time;
    &insertEvent($z,"QUIT");
    exit(0);
  }

  if ($sel =~/[0-9]+/){
    my $vnc;
    if (exists $hash{$sel}){
      print "Capturing screen...\n";
      eval{
      my @parts = split /\:/,$hash{$sel};
        print "Conecting to : $parts[1] ... \n";
        $vnc = Net::VNC->new({hostname=>$parts[1],password=>$parts[2]});
        $vnc->login();
        print "conected ok...\n";
        my $z = time;
        &insertEvent($z,"Screen Capture");
        my $img = $vnc->capture();
        $img->save($data_dir . "/" . $z . ".png"); 
        print "Done!\n";
      };
      if ($@){
        print "error occured capturing screen shot...\n";
      }
    }
  }
}

sub insertEvent{
  my $epoch = shift;
  my $event_type = shift;
  my $optional = shift;

  if (length($optional)==0){
  my $esql = qq{INSERT INTO events(event_epoch,event_type) values (?,?)};
  my $esth = $dbh->prepare($esql);
  $esth->execute($epoch,$event_type);
  } else {
  my $esql = qq{INSERT INTO events(event_epoch,event_type,event_extra) values (?,?,?)};
  my $esth = $dbh->prepare($esql);
  $esth->execute($epoch,$event_type,$optional);

  }
}
