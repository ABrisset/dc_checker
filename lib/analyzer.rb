class Analyzer

  attr_accessor :document

  def initialize
    @page_content = []
    @document = nil
  end

  def get_words_of_document
    @document.apply(:chunk, :segment, :tokenize)
    @document.tokens.each do |t|
      t.words.each do |w|
        @page_content << w.to_s
      end
    end
    @page_content.flatten
  end

  def parse(file)
    array = Array.new(0)
    File.open(file, 'r') do |file|
      file.each_line do |line|
        array << line.chomp
      end
    end
    array
  end

  def remove_stop_words_from(array, stop_words)
    array.delete_if{ |word| stop_words.include?(word) || !word.match(/^[[:alpha:]]+$/) }
  end

  def remove_accents_from(array)
    array.map{ |e| e.to_ascii }
  end
end
