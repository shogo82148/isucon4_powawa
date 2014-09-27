CREATE TABLE IF NOT EXISTS `users` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `login` varchar(255) NOT NULL UNIQUE,
  `password_hash` varchar(255) NOT NULL,
  `salt` varchar(255) NOT NULL,
  fail_count int unsigned NOT NULL DEFAULT 0
) DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `login_log` (
  `id` bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `created_at` datetime NOT NULL,
  `user_id` int,
  `login` varchar(255) NOT NULL,
  `ip` varchar(255) NOT NULL,
  `succeeded` tinyint NOT NULL
) DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS `ips` (
  ip VARCHAR(255) NOT NULL,
  fail_count INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (ip)
) DEFAULT CHARSET=utf8;

CREATE TABLE IF NOT EXISTS success_log (
  id int unsigned not null auto_increment,
  user_id int not null,
  ip varchar(255) not null,
  created_at timestamp not null default current_timestamp,
  primary key (id),
  index (user_id, created_at desc)
) DEFAULT CHARSET=utf8;
