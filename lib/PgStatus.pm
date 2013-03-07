package PgStatus;

# This program is open source, licensed under the PostgreSQL Licence.
# For license terms, see the LICENSE file.

use Mojo::Base 'Mojolicious';

# This method will run once at server start
sub startup {
  my $self = shift;

  # Documentation browser under "/perldoc"
  $self->plugin('PODRenderer');

  # register Helpers plugins namespace
  $self->plugins->namespaces([ "Helpers", @{ $self->plugins->namespaces } ]);

  # Setup charset
  $self->plugin(charset => { charset => 'utf8' });

  # Load HTML Messaging plugin
  $self->plugin('messages');

  # Router
  my $r = $self->routes;

  # Normal route to controller
  $r->get('/')                           ->to('pg#welcome')       ->name('pg_welcome');
  $r->route('/pg_status')                ->to('pg#status')        ->name('pg_status');
  $r->route('/pg_activity')              ->to('pg#activity')      ->name('pg_activity');
  $r->route('/pg_count')                 ->to('pg#count')         ->name('pg_count');
  $r->route('/pg_query/:db/:pid')        ->to('pg#query')         ->name('pg_query');
  $r->route('/pg_toggle/:name')          ->to('pg#toggle')        ->name('pg_toggle');
  $r->route('/pg_backend/:pid/:do')      ->to('pg#backend')       ->name('pg_backend');
  $r->route('/pg_logout')                ->to('pg#logout')        ->name('pg_logout');
}

1;
