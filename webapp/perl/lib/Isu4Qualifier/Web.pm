package Isu4Qualifier::Web;

use 5.16.1;
use warnings;
use utf8;
use Kossy;
use DBIx::Sunny;
use Digest::SHA qw/ sha256_hex /;
use Data::Dumper;
use Redis::Fast;

sub config {
  my ($self) = @_;
  $self->{_config} ||= {
    user_lock_threshold => $ENV{'ISU4_USER_LOCK_THRESHOLD'} || 3,
    ip_ban_threshold => $ENV{'ISU4_IP_BAN_THRESHOLD'} || 10
  };
};

sub db {
  my ($self) = @_;
  my $host = $ENV{ISU4_DB_HOST} || '127.0.0.1';
  my $port = $ENV{ISU4_DB_PORT} || 3306;
  my $username = $ENV{ISU4_DB_USER} || 'root';
  my $password = $ENV{ISU4_DB_PASSWORD};
  my $database = $ENV{ISU4_DB_NAME} || 'isu4_qualifier';

  $self->{_db} ||= do {
    DBIx::Sunny->connect(
      "dbi:mysql:database=$database;host=$host;port=$port", $username, $password, {
        RaiseError => 1,
        PrintError => 0,
        AutoInactiveDestroy => 1,
        mysql_enable_utf8   => 1,
        mysql_auto_reconnect => 1,
      },
    );
  };
}

sub redis {
  state $redis = Redis::Fast->new;
}

sub calculate_password_hash {
  my ($password, $salt) = @_;
  sha256_hex($password . ':' . $salt);
};

sub user_locked {
  my ($self, $user) = @_;
  my $log = $self->db->select_row( 'SELECT user_id FROM locked_users WHERE user_id = ?', $user->{'id'} );
  defined $log->{user_id};
};

sub ip_banned {
  my ($self, $ip) = @_;
  my $log = $self->db->select_row( 'SELECT ip FROM banned_ips WHERE ip = ?', $ip );
  defined $log->{ip};
};

sub attempt_login {
  my ($self, $login, $password, $ip) = @_;

  my $txn = $self->db->txn_scope;
  my $user = $self->db->select_row('SELECT * FROM users WHERE login = ?', $login);

  if ($self->ip_banned($ip)) {
    $self->login_log(0, $login, $ip, $user ? $user->{id} : undef);
    $txn->commit;
    return undef, 'banned';
  }

  if ($self->user_locked($user)) {
    $self->login_log(0, $login, $ip, $user->{id});
    $txn->commit;
    return undef, 'locked';
  }

  if ($user && calculate_password_hash($password, $user->{salt}) eq $user->{password_hash}) {
    $self->login_log(1, $login, $ip, $user->{id});
    $txn->commit;
    return $user, undef;
  }
  elsif ($user) {
    $self->login_log(0, $login, $ip, $user->{id});
    $txn->commit;
    return undef, 'wrong_password';
  }
  else {
    $self->login_log(0, $login, $ip);
    $txn->commit;
    return undef, 'wrong_login';
  }
};

sub current_user {
  my ($self, $user_id) = @_;

  $self->db->select_row('SELECT * FROM users WHERE id = ?', $user_id);
};

sub last_login {
  my ($self, $user_id) = @_;

  my $logs = $self->db->select_all( <<'__EOT__', $user_id );
SELECT a.created_at
     , a.ip
     , b.login
  FROM success_log a
  JOIN users       b ON a.user_id = b.id
 WHERE a.user_id = ?
 ORDER BY a.created_at DESC
 LIMIT 1
OFFSET 1
__EOT__

  @$logs[-1];
};

sub banned_ips {
  my ($self) = @_;
  my $_ips = $self->db->select_all( 'select ip from banned_ips' );
  my @ips = map { $_->{ip} } @$_ips;
  \@ips;
};

sub locked_users {
  my ($self) = @_;
  my $_user_ids = $self->db->select_all( <<'__EOT__' );
SELECT b.login
  FROM locked_users a
  JOIN users        b ON a.user_id = b.id
__EOT__
  my @user_ids = map { $_->{login} } @$_user_ids;
  \@user_ids;
};

sub login_log {
  my ($self, $succeeded, $login, $ip, $user_id) = @_;
#  $self->db->query(
#    'INSERT INTO login_log (`user_id`, `login`, `ip`, `succeeded`) VALUES (?,?,?,?)',
#    $user_id, $login, $ip, ($succeeded ? 1 : 0)
#  );
  if ($succeeded) {
      $self->db->query( 'insert into success_log(user_id, ip) values (?, ?)', $user_id, $ip);
      $self->db->query( 'update failed_users set failures = 0 where user_id = ?', $user_id );
      $self->db->query( 'update failed_ips set failures = 0 where ip = ?', $ip );
  }
  else {
      $self->db->query(
          'insert into failed_ips(ip, failures) values (?, 1)'.
          'on duplicate key update failures = failures + 1',
          $ip );
      my $ips = $self->db->select_row( 'SELECT failures FROM failed_ips WHERE ip = ?', $ip );
      if ($self->config->{ip_ban_threshold} <= ($ips->{failures} // 0)) {
          $self->db->query( 'insert ignore into banned_ips(ip) values (?)', $ip );
      }
#      if (defined $user_id) {
          $self->db->query(
              'insert into failed_users(user_id, failures) values (?, 1)'.
              'on duplicate key update failures = failures + 1',
              $user_id );
          my $users = $self->db->select_row( 'SELECT failures FROM failed_users WHERE user_id = ?', $user_id );
          if ($self->config->{user_lock_threshold} <= ($users->{failures} // 0)) {
              $self->db->query( 'insert ignore into locked_users(user_id) values (?)', $user_id );
          }
#      }
  }
};

sub set_flash {
  my ($self, $c, $msg) = @_;
  $c->req->env->{'psgix.session'}->{flash} = $msg;
};

sub pop_flash {
  my ($self, $c, $msg) = @_;
  my $flash = $c->req->env->{'psgix.session'}->{flash};
  delete $c->req->env->{'psgix.session'}->{flash};
  $flash;
};

filter 'session' => sub {
  my ($app) = @_;
  sub {
    my ($self, $c) = @_;
    my $sid = $c->req->env->{'psgix.session.options'}->{id};
    $c->stash->{session_id} = $sid;
    $c->stash->{session}    = $c->req->env->{'psgix.session'};
    $app->($self, $c);
  };
};

get '/' => [qw(session)] => sub {
  my ($self, $c) = @_;

  $c->render('index.tx', { flash => $self->pop_flash($c) });
};

post '/login' => sub {
  my ($self, $c) = @_;
  my $msg;

  my ($user, $err) = $self->attempt_login(
    $c->req->param('login'),
    $c->req->param('password'),
    $c->req->address
  );

  if ($user && $user->{id}) {
    $c->req->env->{'psgix.session'}->{user_id} = $user->{id};
    $c->redirect('/mypage');
  }
  else {
    if ($err eq 'locked') {
      $self->set_flash($c, 'This account is locked.');
    }
    elsif ($err eq 'banned') {
      $self->set_flash($c, "You're banned.");
    }
    else {
      $self->set_flash($c, 'Wrong username or password');
    }
    $c->redirect('/');
  }
};

get '/mypage' => [qw(session)] => sub {
  my ($self, $c) = @_;
  my $user_id = $c->req->env->{'psgix.session'}->{user_id};
  my $user = $self->current_user($user_id);
  my $msg;

  if ($user) {
    $c->render('mypage.tx', { last_login => $self->last_login($user_id) });
  }
  else {
    $self->set_flash($c, "You must be logged in");
    $c->redirect('/');
  }
};

get '/report' => sub {
  my ($self, $c) = @_;
  $c->render_json({
    banned_ips => $self->banned_ips,
    locked_users => $self->locked_users,
  });
};

get '/init' => sub {
  my ($self, $c) = @_;

  {
    my @ips;
    my $threshold = $self->config->{ip_ban_threshold};
  
    my $not_succeeded = $self->db->select_all('SELECT ip FROM (SELECT ip, MAX(succeeded) as max_succeeded, COUNT(1) as cnt FROM login_log GROUP BY ip) AS t0 WHERE t0.max_succeeded = 0 AND t0.cnt >= ?', $threshold);
  
    foreach my $row (@$not_succeeded) {
      $self->db->query( 'insert ignore into banned_ips(ip) values (?)', $row->{ip} );
    }
  
    my $last_succeeds = $self->db->select_all('SELECT ip, MAX(id) AS last_login_id FROM login_log WHERE succeeded = 1 GROUP by ip');
  
    foreach my $row (@$last_succeeds) {
      my $count = $self->db->select_one('SELECT COUNT(1) AS cnt FROM login_log WHERE ip = ? AND ? < id', $row->{ip}, $row->{last_login_id});
      if ($threshold <= $count) {
       $self->db->query( 'insert ignore into banned_ips(ip) values (?)', $row->{ip} );
      }
    }
  }
  {
    my @user_ids;
    my $threshold = $self->config->{user_lock_threshold};
  
    my $not_succeeded = $self->db->select_all('SELECT user_id, login FROM (SELECT user_id, login, MAX(succeeded) as max_succeeded, COUNT(1) as cnt FROM login_log GROUP BY user_id) AS t0 WHERE t0.user_id IS NOT NULL AND t0.max_succeeded = 0 AND t0.cnt >= ?', $threshold);
  
    foreach my $row (@$not_succeeded) {
      $self->db->query( 'insert ignore into locked_users(user_id) values (?)', $row->{user_id} );
    }
  
    my $last_succeeds = $self->db->select_all('SELECT user_id, login, MAX(id) AS last_login_id FROM login_log WHERE user_id IS NOT NULL AND succeeded = 1 GROUP BY user_id');
  
    foreach my $row (@$last_succeeds) {
      my $count = $self->db->select_one('SELECT COUNT(1) AS cnt FROM login_log WHERE user_id = ? AND ? < id', $row->{user_id}, $row->{last_login_id});
      if ($threshold <= $count) {
        $self->db->query( 'insert ignore into locked_users(user_id) values (?)', $row->{user_id} );
      }
    }
  }
};

1;
