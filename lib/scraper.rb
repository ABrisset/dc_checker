class Scraper
  def get_content_of(page)
    page.doc
        .xpath('//comment()')
        .remove
    page.doc
        .at('body')
        .search('//script|//noscript|//style')
        .remove
    HTMLEntities.new.decode(page.doc
                                .to_html
                                .gsub(/<[^>]+>/, "\s")
                                .downcase)
  end
end
