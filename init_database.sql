create database IPsniffer;

CREATE  TABLE IF NOT EXISTS `ip_data` (
  `id` INT NOT NULL AUTO_INCREMENT ,
  `ip_from` DOUBLE NOT NULL ,
  `ip_to` DOUBLE NOT NULL ,
  `country_code` CHAR(2) NULL ,
  `country_name` VARCHAR(64) NULL ,
  `region` VARCHAR(128) NULL ,
  `city` VARCHAR(128) NULL ,
  `isp_name` VARCHAR(256) NULL ,
  `domain_name` VARCHAR(128) NULL ,
  `mcc` VARCHAR(128) NULL ,
  `mnc` VARCHAR(128) NULL ,
  `mobile_brand` VARCHAR(128) NULL ,
  PRIMARY KEY (`id`) ,
  INDEX `city` (`city` ASC) ,
  INDEX `country_name` (`country_name` ASC) ,
  INDEX `mobile_brand` (`mobile_brand` ASC) ,
  INDEX `ip_address` (`ip_from` ASC, `ip_to` ASC)
) ENGINE = MyISAM
