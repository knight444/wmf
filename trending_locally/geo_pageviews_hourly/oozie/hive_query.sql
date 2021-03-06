set hive.stats.autogather=false;
USE ${database};

ADD JAR hdfs:///wmf/refinery/current/artifacts/refinery-hive.jar;
CREATE TEMPORARY FUNCTION parse_ua as 'org.wikimedia.analytics.refinery.hive.UAParserUDF';
CREATE TEMPORARY FUNCTION geocode as 'org.wikimedia.analytics.refinery.hive.GeocodedCountryUDF';
CREATE TEMPORARY FUNCTION is_crawler as 'org.wikimedia.analytics.refinery.hive.IsCrawlerUDF';
CREATE TEMPORARY FUNCTION get_access_method as 'org.wikimedia.analytics.refinery.hive.GetAccessMethodUDF';
CREATE TEMPORARY FUNCTION  resolve_ip as 'org.wikimedia.analytics.refinery.hive.ClientIpUDF';

CREATE TEMPORARY MACRO get_project(uri_host STRING)
    reverse(split(reverse(uri_host), '\\.')[1]);

CREATE TEMPORARY MACRO get_variant(uri_host STRING)
    REGEXP_EXTRACT(uri_host, '(www\\.)?(((?:(?!m\\.|zero\\.|wap\\.|mobile\\.)[^.])*)\\.)?((m|zero|wap|mobile)\\.)?(wikipedia|wiktionary|wikibooks|wikinews|wikiquote|wikisource|wikiversity|wikivoyage|wikimedia|wikidata)\\.org(:80)?', 3);


CREATE TABLE IF NOT EXISTS ellery.geo_pageviews_${version} (
  project STRING,
  variant STRING,
  page_title STRING,
  access_method STRING,
  country STRING,
  n INT)
PARTITIONED BY (year INT, month INT, day INT, hour INT);



DROP TABLE IF EXISTS ellery.geo_pageviews_${year}_${month}_${day}_${hour}_${version};

CREATE TABLE ellery.geo_pageviews_${year}_${month}_${day}_${hour}_${version} (
  project STRING,
  variant STRING,
  page_title STRING,
  access_method STRING,
  country STRING,
  n INT
);

INSERT INTO TABLE ellery.geo_pageviews_${year}_${month}_${day}_${hour}_${version}
  SELECT project, variant, page_title, access_method, country, count(*) as n FROM
  (SELECT
    get_project(uri_host) as project,
    get_variant(uri_host) as variant,
    REGEXP_EXTRACT(reflect("java.net.URLDecoder", "decode", uri_path), '^/[^/]*/(.*)', 1) as page_title,
    get_access_method(uri_host, user_agent) as access_method,
    geocode(resolve_ip(ip, x_forwarded_for)) as country
    FROM wmf.webrequest TABLESAMPLE(BUCKET 1 OUT OF 64 ON rand())
    WHERE year = ${year}
    AND month = ${month}
    AND day = ${day}
    AND hour = ${hour}
    AND uri_path NOT RLIKE '^/w/'
    AND is_pageview
    AND is_crawler(user_agent) = 0
    AND parse_ua(user_agent)['device_family'] != 'Spider') a
  GROUP BY project, variant, page_title, access_method, country;


INSERT INTO TABLE ellery.geo_pageviews_${version}
PARTITION (year = ${year}, month = ${month}, day = ${day}, hour = ${hour})
SELECT * FROM ellery.geo_pageviews_${year}_${month}_${day}_${hour}_${version};

DROP TABLE ellery.geo_pageviews_${year}_${month}_${day}_${hour}_${version};
