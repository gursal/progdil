require 'erb'
require 'yaml'
task :exam do
  Dir.foreach("_exams") do |dizin|
  if not dizin == '.' || dizin == '..'
    # puts dizin
    config = YAML.load_file("_exams/" + dizin)
    baslik = config["title"]

    alt = config["footer"]
    sorular = config["q"]
    k=0
    soru_list = []
    for i in sorular
      okuu = File.read("_includes/q/" + i)
      soru_list[k] = okuu
      k = k+1
    end

    oku = File.read("_templates/exam.md.erb")

    yeni = ERB.new(oku)

    f = File.open("gecici.md", "w")
    f.write(yeni.result(binding))
    f.close
    sh "markdown2pdf gecici.md -o #{dizin}"
    sh "rm -f gecici.md"
  end
  end
end

task :default => :exam
