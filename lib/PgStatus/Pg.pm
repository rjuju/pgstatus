package PgStatus::Pg;

# This program is open source, licensed under the PostgreSQL Licence.
# For license terms, see the LICENSE file.

use Mojo::Base 'Mojolicious::Controller';
use DBI;
use Switch;
use Data::Dumper;

sub check_auth {
    my $self = shift;

    # Make the dispatch continue when the pg version is found in the session
    if ( defined($self->session('pg_version')) ) {
        return 1;
    }

    $self->redirect_to('pg_welcome');
    return 0;
}

sub database {
    my $self = shift;
    my $datname = shift;
    my $dbh;

    my $conninfo =conninfo( (defined $datname ? $datname : $self->session('pg_database') ),$self->session('pg_host'),$self->session('pg_port'));
    $dbh = DBI->connect( $conninfo, $self->session('pg_username'), $self->session('pg_password'));
    if ( $dbh ) {
        my $sql =$dbh->prepare(qq{select substr(version(),12,1) || substr(version(),14,1) AS v;});
        $sql->execute();
        my $version = $sql->fetchrow();
        $sql->finish();
        $self->session('pg_version' => $version);
    } else {
        $self->msg->error("Could not connect to database.");
        $self->session('pg_version' => undef);
    }

    return $dbh;
}

sub welcome {
    my $self = shift;
    my $method = $self->req->method;
    my $dbh;
    my $version;
    my $sql;

    if ($method =~ m/^POST$/) {
        #Try to connect
        my $param = $self->req->params->to_hash;
        my $error = 0;
        my $msg = "";

        #Connections settings
        $self->session('pg_username' => $param->{username});
        $self->session('pg_host' => $param->{host});
        $self->session('pg_port' => $param->{port});
        $self->session('pg_database' => $param->{database});
        $self->session('pg_password' => $param->{password});
        #$self->session('pg_version' => $version);
        #Display settings
        $self->session('prm_idle' => 1);
        $self->session('prm_idle_transaction' => 1);
        $self->session('prm_active' => 1);
        $self->session('prm_waiting' => 1);

        $dbh = database($self);

        if (! $dbh){
            return $self->redirect_to('/');
        } else{
            $dbh->disconnect();
            return $self->redirect_to('/pg_status');
        }
    }
    return $self->redirect_to('pg_status') if ( defined($self->session('pg_version')) );
    return $self->render();
}

# main page
sub status {
    my $self = shift;
    my $dbh;
    my $version;
    my $sql;

#Connection already ok, get by session
    $version = $self->session('pg_version');

    return $self->render();
}

sub activity {
    my $self = shift;
    my $version = $self->session('pg_version');
    my $sql;
    my $dbh = database($self);
    if (! $dbh){
        $self->msg->error("Could not connect to database.");
      return $self->redirect_to('/');
    }
  my $queries = [ ];
  if ($version > 91){
    $sql = $dbh->prepare(qq{SELECT pid,datname,usename,state,query,waiting::text
      FROM pg_stat_activity
      WHERE pid <> pg_backend_pid();});
  }
  else{
    $sql = $dbh->prepare(qq{SELECT procpid AS pid,datname,usename,
      CASE current_query
        WHEN '<IDLE>' THEN 'idle'
        WHEN '<IDLE> in transaction' THEN 'idle in transaction'
        ELSE 'active'
      END as state,current_query AS query,waiting::text as waiting
      FROM pg_stat_activity
      WHERE procpid <> pg_backend_pid();});
  }
  $sql->execute();
  my $add;

  while ( my $row = $sql->fetchrow_hashref() ) {
    $add = 0;
    switch ($row->{status}){
      case "idle" { $add = 1 if ($self->session('prm_idle')); }
      case "idle in transaction" { $add = 1 if ($self->session('prm_idle_transaction')); }
      case "active" { $add = 1 if ($self->session('prm_active')); }
      else { $add = 1; }
      }
    $add = 1 if (($self->session('prm_waiting')) && ($row->{waiting} eq "true"));
    if ($add){
      push @{$queries},  $row;
    }
  }
  $sql->finish();
  $self->stash(queries => $queries);
  $dbh->disconnect();
  $self->render();
}

sub count {
  my $self = shift;
  my $version = $self->session('pg_version');
  my $sql;
  my $count = 0;
  my $count_idle = 0;
  my $count_idle_transaction = 0;
  my $count_active = 0;
  my $count_waiting = 0;
  my $count_other = 0;
  my $dbh = database($self);
  if (! $dbh){
   $self->msg->error("Could not connect to database.");
    return $self->redirect_to('/');
  }
  my $field_state = "";
  my $field_pid = "pid";
  if ($self->session('pg_version') < 92){
    $field_state = qq{CASE current_query
      WHEN '<IDLE>' THEN 'idle'
      WHEN '<IDLE> in transaction' THEN 'idle in transaction'
      ELSE 'active'
      END AS };
      $field_pid = "procpid";
  }
  my $tmp = "SELECT ".$field_state.qq{state,COUNT(*) as c
    FROM pg_stat_activity
  WHERE }.$field_pid.qq{ <> pg_backend_pid()
  GROUP BY state;};

  $sql = $dbh->prepare($tmp);
  $sql->execute();
  while (my ($k, $v) = $sql->fetchrow()) {
    $count+=$v;
    switch ($k){
      case "idle"   { $count_idle+=$v; }
      case "idle in transaction"   { $count_idle_transaction+=$v; }
      case "active"   { $count_active+=$v; }
      else  { $count_other +=$v; }
    }
  }
  $sql->finish();
  $sql = $dbh->prepare("SELECT COUNT(*) FROM pg_stat_activity WHERE waiting;");
  $sql->execute();
  $count_waiting = $sql->fetchrow();
  $sql->finish();
  $dbh->disconnect();
  $self->render_json({count => $count,
    count_idle => $count_idle,
    count_idle_transaction => $count_idle_transaction,
    count_active => $count_active,
    count_waiting => $count_waiting,
    count_other => $count_other
  });

}

sub query {
    my $self = shift;
    my $dbname = $self->param('db');
    my $pid = $self->param('pid');
    my $field_pid = (($self->session('pg_version') > 91)?"pid":"procpid");
    my $field_query = (($self->session('pg_version') > 91)?"query":"current_query");

    my $dbh = database($self,$dbname);
    if (! $dbh){
      #Could not connect to specific database
      $dbh = database($self);
    }
    my $tmp = "SELECT $field_query as query FROM pg_stat_activity WHERE $field_pid = $pid";
    my $sql = $dbh->prepare($tmp);
    $sql->execute();
    my $query = $sql->fetchrow();
    $self->stash(query => $query);

    $tmp = qq{SELECT quote_ident(n.nspname) || '.' || quote_ident(c.relname) as relname,
      quote_ident(psa.datname) as datname,l.locktype, l.page,l.tuple,l.mode,l.granted::text,l2.pid as blocking_pid,psa2.}
      .(($self->session('pg_version') > 91)?"query":"current_query")." AS blocking_query\n"
      ." FROM pg_stat_activity psa"
      ." LEFT JOIN pg_locks l ON l.pid = psa.$field_pid"
      .qq{ LEFT JOIN pg_locks l2 ON (l.database,l.relation) = (l2.database,l2.relation)
              AND l2.granted AND NOT l.granted
      LEFT JOIN pg_stat_activity psa2 ON l2.pid = psa2.}.$field_pid
      .qq{ LEFT JOIN pg_class c ON l.relation = c.oid
      LEFT JOIN pg_namespace n ON c.relnamespace = n.oid
      WHERE psa.}.$field_pid." = $pid;";

    $sql = $dbh->prepare($tmp);
    my $lines = [ ];
    $sql->execute();

    my $row;
    push @{$lines}, $row while $row = $sql->fetchrow_hashref();

    $sql->finish();
    $self->stash(lines => $lines);
    $dbh->disconnect();
    $self->render();
}

sub toggle {
  my $self = shift;
  my $name = $self->param('name');
  $self->session('prm_'.$name => ! $self->session('prm_'.$name));
  $self->render();
}

sub backend {
  my $self = shift;
  my $pid = $self->param('pid');
  my $do = $self->param('do');
  my $dbh = database($self);
  if (! $dbh){
   $self->msg->error("Could not connect to database.");
    return;
  }
  my $sql;
  switch ($do){
    case 'cancel' {
      $sql = $dbh->prepare("SELECT pg_cancel_backend($pid);");
      $sql->execute();
      $sql->finish();
    }
    case 'terminate' {
      if ($self->session('pg_version') > 83){
        $sql = $dbh->prepare("SELECT pg_terminate_backend($pid);");
        $sql->execute();
        $sql->finish();
      } else{
        $self->msg->error("Postgres minimum version 8.3 required.");
      }
    }
  }
  $dbh->disconnect();
  $self->render();
}

sub logout {
  my $self = shift;
  $self->session('pg_version'=> undef);
  return $self->redirect_to('/');
}

sub conninfo {
  my ($db,$host,$port,$name,$pass) = @_;
  my $ret = "dbi:Pg:";
  $ret .="dbname=\"$db\";" if ($db ne "");
  $ret .="host=$host;" if ($host ne "");
  $ret .="port=$port;" if ($port ne "");
  return $ret;
}

1;
