#!/usr/bin/env ruby

require 'anemone'
require 'htmlentities'
require 'jaccard'
require 'mysql2'
require 'similarity'
require 'stanford-core-nlp'
require 'treat'
require 'unidecoder'
require 'yaml'

require_relative 'lib/analyzer'
require_relative 'lib/scraper'

include Treat::Core::DSL

Treat.core.language.default = "french"

unless ARGV.length == 2
  puts "Two arguments are required :
=> 1. root URL
=> 2. db name"
  exit
end

## Arguments
root_url  = ARGV[0]
db        = ARGV[1]

## MySQL setup
$connection = Mysql2::Client.new(YAML::load_file("config/database.yml")["development"])
$connection.query("CREATE DATABASE IF NOT EXISTS #{db} CHARACTER SET utf8")
$connection.select_db("#{db}")

## "Pages" table
$connection.query("DROP TABLE pages")
$connection.query("CREATE TABLE pages(
                    id INT PRIMARY KEY AUTO_INCREMENT,
                    absolute_url TEXT CHARACTER SET utf8,
                    content TEXT CHARACTER SET utf8,
                    cosine_id BIGINT)")
$connection.query("CREATE INDEX index_absolute_url ON pages (absolute_url(10));")
$connection.query("CREATE INDEX index_cosine_id ON pages (cosine_id);")

## "Similarity" table
$connection.query("DROP TABLE similarity")
$connection.query("CREATE TABLE similarity(
                    id INT PRIMARY KEY AUTO_INCREMENT,
                    url_a TEXT CHARACTER SET utf8,
                    url_b TEXT CHARACTER SET utf8,
                    salton_cosine FLOAT,
                    jaccard FLOAT)")
$connection.query("CREATE INDEX index_url_a ON similarity (url_a(10));")
$connection.query("CREATE INDEX index_url_b ON similarity (url_b(10));")
$connection.query("TRUNCATE TABLE similarity")

# Delete existing txt files
Dir.glob('pages/*.txt').each do |file|
  File.delete(file)
end

# Start crawl
Anemone.crawl(root_url, :redirect_limit => 1) do |anemone|
  skipped_links = %r{%23.*|\#.*|.*\.(pdf|jpg|jpeg|png|gif)}
  anemone.skip_links_like(skipped_links)
  anemone.on_every_page do |page|
    if page.html? && [200,304].include?(page.code)
      # Catch absolute URL
      absolute_url = URI.decode(page.url.to_s)
      puts absolute_url

      # Scrape content
      scraper = Scraper.new
      content = scraper.get_content_of(page)

      # Save file
      File.open("pages/#{page}.txt", 'w') { |file| file.write(content) }

      # Get words
      analyzer          = Analyzer.new
      analyzer.document = document "pages/#{page}.txt"
      stop_words        = analyzer.parse('stop_words.txt')
      words             = analyzer.get_words_of_document
      words             = analyzer.remove_stop_words_from(words, stop_words)
      words             = analyzer.remove_accents_from(words)
      words             = $connection.escape(words.join(" "))

      ## Fill "pages" table
      $connection.query("INSERT INTO
        pages(
          absolute_url,
          content
        )
        VALUES(
          '#{absolute_url}',
          '#{words}'
        )"
      )
    end
  end
end

## Fill similarity table
pages_a = $connection.query("SELECT absolute_url FROM pages")
                     .map{ |row| row['absolute_url'] }
pages_b = pages_a.dup

pages_a.product(pages_b)
       .map{ |arr| arr.sort }
       .uniq
       .delete_if{ |arr| arr[0] == arr[1] }
       .each do |line|
          url_a = line[0]
          url_b = line[1]
          $connection.query("INSERT INTO
            similarity(
              url_a,
              url_b
            )
            VALUES(
              '#{url_a}',
              '#{url_b}'
            )"
          )
        end

## Compute salton cosine
corpus        = Corpus.new
array_of_docs = Array.new
pages         = $connection.query("SELECT absolute_url,content FROM pages")
pages.each do |row|
  absolute_url  = row['absolute_url']
  content       = row['content']
  document      = Document.new(:content => content)
  corpus        << document
  array_of_docs << document
  cosine_id = document.id
  $connection.query("UPDATE pages
                     SET cosine_id      = '#{cosine_id}'
                     WHERE absolute_url = '#{absolute_url}'")
end

array_of_docs.each do |doc|
  corpus.similar_documents(doc).each do |d, similarity|
    doc_a = doc.id
    doc_b = d.id
    $connection.query("UPDATE similarity
                       SET salton_cosine = '#{similarity}'
                       WHERE url_a =
                        (
                          SELECT absolute_url
                          FROM pages
                          WHERE cosine_id = '#{doc_a}'
                        )
                       AND url_b =
                        (
                          SELECT absolute_url
                          FROM pages
                          WHERE cosine_id = '#{doc_b}'
                        )
                      ")
  end
end

## Compute jaccard coefficient index
pages = $connection.query("SELECT url_a,url_b FROM similarity")
pages.each do |row|
  content_a = ""
  content_b = ""
  url_a     = row["url_a"]
  url_b     = row["url_b"]
  $connection.query("SELECT content
                     FROM pages
                     WHERE absolute_url = '#{url_a}'")
             .each{ |row|  content_a = row["content"].split(" ") }
  $connection.query("SELECT content
                     FROM pages
                     WHERE absolute_url = '#{url_b}'")
             .each{ |row| content_b = row["content"].split(" ") }
  jaccard = Jaccard.coefficient(content_a, content_b)
  $connection.query("UPDATE similarity
                     SET jaccard = '#{jaccard}'
                     WHERE url_a = '#{url_a}'
                     AND url_b   = '#{url_b}'")
end
