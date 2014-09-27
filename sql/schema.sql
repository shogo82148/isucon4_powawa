-- user list
CREATE TABLE IF NOT EXISTS `users` (
  `id` int NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `login` varchar(255) NOT NULL UNIQUE,
  `password_hash` varchar(255) NOT NULL,
  `salt` varchar(255) NOT NULL
) DEFAULT CHARSET=utf8;

-- login log
CREATE TABLE IF NOT EXISTS `login_log` (
  `id` bigint NOT NULL AUTO_INCREMENT PRIMARY KEY,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `user_id` int,
  `login` varchar(255) NOT NULL,
  `ip` varchar(255) NOT NULL,
  `succeeded` tinyint NOT NULL
) DEFAULT CHARSET=utf8;

-- current fails ip
CREATE TABLE IF NOT EXISTS `failed_ips` (
  ip VARCHAR(255) NOT NULL,
  failures INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (ip)
) DEFAULT CHARSET=utf8;

-- current fails of user
CREATE TABLE IF NOT EXISTS failed_users (
  user_id INT NOT NULL,
  failures INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id)
) DEFAULT CHARSET=utf8;

-- for detect last login
CREATE TABLE IF NOT EXISTS success_log (
  id int unsigned not null auto_increment,
  user_id int not null,
  ip varchar(255) not null,
  created_at timestamp not null default current_timestamp,
  primary key (id),
  index (user_id, created_at desc)
) DEFAULT CHARSET=utf8;

-- banned ip list
CREATE TABLE IF NOT EXISTS banned_ips (
  ip varchar(255),
  primary key (ip)
) DEFAULT CHARSET=utf8;

-- locked user list;
CREATE TABLE IF NOT EXISTS locked_users (
  user_id int not null,
  primary key (user_id)
) DEFAULT CHARSET=utf8;
