#!/usr/bin/env ruby

require 'anemone'
require 'csv'
require 'htmlentities'
require 'jaccard'
require 'stanford-core-nlp'
require 'treat'
require 'unidecoder'
require 'yaml'

require_relative 'lib/analyzer'
require_relative 'lib/scraper'

include Treat::Core::DSL

Treat.core.language.default = "french"

unless ARGV.length == 1
  puts "One argument is required :
=> 1. root URL"
  exit
end

## Arguments
root_url  = ARGV[0]

## Delete existing txt files
Dir.glob('pages/*.txt').each do |file|
  File.delete(file)
end

# Creat hash of content
hash_of_content = Hash.new

## Start crawl
Anemone.crawl(root_url, :redirect_limit => 1, :threads => 3) do |anemone|
  skipped_links = %r{%23.*|\#.*|.*\.(pdf|jpg|jpeg|png|gif)}
  anemone.skip_links_like(skipped_links)
  anemone.on_every_page do |page|
    if page.html? && [200,304].include?(page.code)

      ## Catch absolute URL
      absolute_url = URI.decode(page.url.to_s)
      puts absolute_url

      ## Scrape content
      scraper = Scraper.new
      content = scraper.get_content_of(page)

      ## Save file
      File.open("pages/#{page}.txt", 'w') { |file| file.write(content) }

      ## Get words
      analyzer          = Analyzer.new
      analyzer.document = document "pages/#{page}.txt"
      stop_words        = analyzer.parse('stop_words.txt')
      words             = analyzer.get_words_of_document
      words             = analyzer.remove_stop_words_from(words, stop_words)
      words             = analyzer.remove_accents_from(words)

      ## Fill hash of content
      hash_of_content[absolute_url] = words
    end
  end
end

## Get list of URL
pages_a = hash_of_content.keys
pages_b = pages_a.dup

## Get results
results = []
pages_a.product(pages_b)
       .uniq
       .each do |line|
          url_a     = line[0]
          url_b     = line[1]
          content_a = hash_of_content[url_a]
          content_b = hash_of_content[url_b]
          jaccard   = Jaccard.coefficient(content_a, content_b)
          results   << [url_a, url_b, jaccard]
        end

## Fill CSV file
CSV.open("./content.csv", "wb", {:col_sep => ";"}) do |csv|
  results.each do |r|
    csv << [r[0], r[1], r[2]]
  end
end
