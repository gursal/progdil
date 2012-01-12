# kullanilacak kitapliklari (ya da siniflari) ice aktariyor
require 'pathname'
require 'pythonconfig'
require 'yaml'

CONFIG = Config.fetch('presentation', {})

# directory nin icindekileri aliyor
PRESENTATION_DIR = CONFIG.fetch('directory', 'p')
# ontanimli olarak ayarlari cagiriyor
DEFAULT_CONFFILE = CONFIG.fetch('conffile', '_templates/presentation.cfg')
#presentation_dir dan gelen dosyayi index.html ile birlestiriyor
INDEX_FILE = File.join(PRESENTATION_DIR, 'index.html')
#resimler icin boyut sinirlamasi yapiyor
IMAGE_GEOMETRY = [ 733, 550 ]

DEPEND_KEYS    = %w(source css js)

DEPEND_ALWAYS  = %w(media)
# rakefile icin gorev tanimlamalari yapiliyor
TASKS = {
    :index   => 'sunumları indeksle',
    :build   => 'sunumları oluştur',
    :clean   => 'sunumları temizle',
    :view    => 'sunumları görüntüle',
    :run     => 'sunumları sun',
    :optim   => 'resimleri iyileştir',
    :default => 'öntanımlı görev',
}
# slaytlar ve indexlemelerin hangi etiketlerde tutulacagini tanimladik..
# sozluk yapisiyla.
presentation   = {}
tag            = {}
#dosya sinifi olusturuldu. bu sinifta dosyalarin secim ve  bunlarin listelenmesi
#yapildi...
class File
#kesin dosya yolunu aliyoruz
  @@absolute_path_here = Pathname.new(Pathname.pwd) #
  def self.to_herepath(path)
    Pathname.new(File.expand_path(path)).relative_path_from(@@absolute_path_here).to_s
  end
  def self.to_filelist(path) #verilen yolla dosya listelemsi yapiliyor
    File.directory?(path) ?
      FileList[File.join(path, '*')].select { |f| File.file?(f) } :
      [path]
  end
end

#png yorumlamalari icin fonksiyon tanimlaniyor...
def png_comment(file, string)
  require 'chunky_png'
  require 'oily_png'

  image = ChunkyPNG::Image.from_file(file)
  image.metadata['Comment'] = 'raked'
  image.save(file)
end
# resim optimizasyonlarinin yapilmasi icin fonksiyonlar tanimlaniyor.. ayni
# isimli dosyalar varsa yeniden isimlendiriliyor eski dosyayi siliyor
def png_optim(file, threshold=40000)
  return if File.new(file).size < threshold
  sh "pngnq -f -e .png-nq #{file}"
  out = "#{file}-nq"
  if File.exist?(out)
    $?.success? ? File.rename(out, file) : File.delete(out)
  end
  png_comment(file, 'raked')
end
# jpg uzantili dosyalarin optimizasyonu bu fonksiyonda yapiliyor.. resme rake
# edildigi belirtiliyor
def jpg_optim(file)
  sh "jpegoptim -q -m80 #{file}"
  sh "mogrify -comment 'raked' #{file}"
end
# optimize adilmis dosyalarin listelenmesi yapiliyor
# resimleri teker teker alip IMAGE_GEOMETRY de tanimlasmis degerle
# karsilastiriyor ve buyukse yeniden boyutlandiriyor
def optim
  pngs, jpgs = FileList["**/*.png"], FileList["**/*.jpg", "**/*.jpeg"]

  [pngs, jpgs].each do |a|
    a.reject! { |f| %x{identify -format '%c' #{f}} =~ /[Rr]aked/ }
  end

  (pngs + jpgs).each do |f|
    w, h = %x{identify -format '%[fx:w] %[fx:h]' #{f}}.split.map { |e| e.to_i }
    size, i = [w, h].each_with_index.max
    if size > IMAGE_GEOMETRY[i]
      arg = (i > 0 ? 'x' : '') + IMAGE_GEOMETRY[i].to_s
      sh "mogrify -resize #{arg} #{f}"
    end
  end
# optimize adilmis resimleri outputtan birsey basmadan dokunuyor. yani
  # duzenlenme tarihlerinde degisiklik yapikyor.
  pngs.each { |f| png_optim(f) }
  jpgs.each { |f| jpg_optim(f) }

  (pngs + jpgs).each do |f|
    name = File.basename f
    FileList["*/*.md"].each do |src|
      sh "grep -q '(.*#{name})' #{src} && touch #{src}"
    end
  end
end


# ayar dosyasini aliyor
default_conffile = File.expand_path(DEFAULT_CONFFILE)

FileList[File.join(PRESENTATION_DIR, "[^_.]*")].each do |dir|
  next unless File.directory?(dir)
  chdir dir do
    name = File.basename(dir)
    conffile = File.exists?('presentation.cfg') ? 'presentation.cfg' : default_conffile
    config = File.open(conffile, "r") do |f|
      PythonConfig::ConfigParser.new(f)
    end
# landslide programina gore konfigurasyonunu ayarla eger landslide
    # tanimlanmis degilse standart hata ciktisi bas ve programdan 1 ile cik
    landslide = config['landslide']
    if ! landslide
      $stderr.puts "#{dir}: 'landslide' bölümü tanımlanmamış"
      exit 1
    end

    if landslide['destination']
      $stderr.puts "#{dir}: 'destination' ayarı kullanılmış; hedef dosya belirtilmeyin"
      exit 1
    end
# index dosyasinin olup olmadigini kontrol et varsa disispublic degerini true
    # yap ayni sekilde presentation dosyasini kontrol et varsa ispublic i
    # false yap. eger bunlar yoksa standart hata ciktisi bas...
    if File.exists?('index.md')
      base = 'index'
      ispublic = true
    elsif File.exists?('presentation.md')
      base = 'presentation'
      ispublic = false
    else
      $stderr.puts "#{dir}: sunum kaynağı 'presentation.md' veya 'index.md' olmalı"
      exit 1
    end
# indexten base degiskeni ile gelen ismin sonuna .html ekleyerek tarayicida
    # goruntuleyebiliyoruz.
    basename = base + '.html'
    thumbnail = File.to_herepath(base + '.png')
    target = File.to_herepath(basename)
# bagimli bagimlilik verilercek dosya yollari icin deps listesi aciliyor.
    deps = []
    (DEPEND_ALWAYS + landslide.values_at(*DEPEND_KEYS)).compact.each do |v|
      deps += v.split.select { |p| File.exists?(p) }.map { |p| File.to_filelist(p) }.flatten
    end
# deps den gelen yollari goreceli yapildi ve kucuk resimleri sildi..
    deps.map! { |e| File.to_herepath(e) }
    deps.delete(target)
    deps.delete(thumbnail)
#etiket listesi tanimlandi
   tags = []

   presentation[dir] = {
      :basename  => basename,	# üreteceğimiz sunum dosyasının baz adı
      :conffile  => conffile,	# landslide konfigürasyonu (mutlak dosya yolu)
      :deps      => deps,	# sunum bağımlılıkları
      :directory => dir,	# sunum dizini (tepe dizine göreli)
      :name      => name,	# sunum ismi
      :public    => ispublic,	# sunum dışarı açık mı
      :tags      => tags,	# sunum etiketleri
      :target    => target,	# üreteceğimiz sunum dosyası (tepe dizine göreli)
      :thumbnail => thumbnail, 	# sunum için küçük resim
    }
  end
end

# sunumlarin herbiri icin tags islemini yapiyor
presentation.each do |k, v|
  v[:tags].each do |t|
    tag[t] ||= []
    tag[t] << k
  end
end

tasktab = Hash[*TASKS.map { |k, v| [k, { :desc => v, :tasks => [] }] }.flatten]
#landslide komutuyla sunum dosyalari hazirlaniyor.
presentation.each do |presentation, data|
  ns = namespace presentation do
    file data[:target] => data[:deps] do |t|
      chdir presentation do
        sh "landslide -i #{data[:conffile]}"
        sh 'sed -i -e "s/^\([[:blank:]]*var hiddenContext = \)false\(;[[:blank:]]*$\)/\1true\2/" presentation.html'
# sunumlarin ismi presentation.html degilde ismini degistir
        unless data[:basename] == 'presentation.html'
          mv 'presentation.html', data[:basename]
        end
      end
    end
#kucuk resimler ilgili yere gonderildi ilgili duzenlemeler yapiliyor web
    #sayfasi olusturmak icin cutycapt ile resmin adresi boyutlari vs. ayarlanmis
    file data[:thumbnail] => data[:target] do
      next unless data[:public]
      sh "cutycapt " +
          "--url=file://#{File.absolute_path(data[:target])}#slide1 " +
          "--out=#{data[:thumbnail]} " +
          "--user-style-string='div.slides { width: 900px; overflow: hidden; }' " +
          "--min-width=1024 " +
          "--min-height=768 " +
          "--delay=1000"
      sh "mogrify -resize 240 #{data[:thumbnail]}"
      png_optim(data[:thumbnail])
    end
# ust tarafta tanimlanan gorevlerin rake file icin tanimlamalari yapildi.
    task :optim do
      chdir presentation do
        optim
      end
    end
# resim bilgilerini al
    task :index => data[:thumbnail]
# insa et optimize et target yani hedefteki bilgileri al intexle..
    task :build => [:optim, data[:target], :index]
# goruntuleme dosyasinin kontrolu.. yoksa std err e hata bas..
    task :view do
      if File.exists?(data[:target])
        sh "touch #{data[:directory]}; #{browse_command data[:target]}"
      else
        $stderr.puts "#{data[:target]} bulunamadı; önce inşa edin"
      end
    end
# calistir ve goruntule..
    task :run => [:build, :view]
# clean temizleme gorevi tanimlamasi yapildi.. hedef ve resim bilgilerini
    # sil.
    task :clean do
      rm_f data[:target]
      rm_f data[:thumbnail]
    end
# komut satirina rake yazildiginde gerceklesecek default forev atamasi :build
    task :default => :build
  end
# gorev haritasina verilen gorevlerin eklenmesi
  ns.tasks.map(&:to_s).each do |t|
    _, _, name = t.partition(":").map(&:to_sym)
    next unless tasktab[name]
    tasktab[name][:tasks] << t
  end
end
#isim uzayinda gorev listesinin elemanlari icin yeni gorevler belirle
namespace :p do
  tasktab.each do |name, info|
    desc info[:desc]
    task name => info[:tasks]
    task name[0] => name
  end
# rake build gorev tanimlamasi yapildi. INDEX_FILE degiskenindeki yml
  # dosyasini yukle. sonra sunum seciliyor. index esit degilse 'w' ile
  # yazilabilir olan INDEX_FILE dosyasini ac ve icine index.to_yaml dosyasini
  # yaz arkasina da  "---\n" yaz
  task :build do
    index = YAML.load_file(INDEX_FILE) || {}
    presentations = presentation.values.select { |v| v[:public] }.map { |v| v[:directory] }.sort
    unless index and presentations == index['presentations']
      index['presentations'] = presentations
      File.open(INDEX_FILE, 'w') do |f|
        f.write(index.to_yaml)
        f.write("---\n")
      end
    end
  end
# aciklama bolumu olusturuldu.
  desc "sunum menüsü"
  task :menu do
    lookup = Hash[
      *presentation.sort_by do |k, v|
        File.mtime(v[:directory])
      end
      .reverse
      .map { |k, v| [v[:name], k] }
      .flatten
    ]
# aciklama bolumunden menu secimi yapiliyor. default olarak 1 ataniyor..
    # sunum secme ve renk ayarlamalari ve ozel secenekler verilmis...
    name = choose do |menu|
      menu.default = "1"
      menu.prompt = color(
        'Lütfen sunum seçin ', :headline
      ) + '[' + color("#{menu.default}", :special) + ']'
      menu.choices(*lookup.keys)
    end
    directory = lookup[name]

    Rake::Task["#{directory}:run"].invoke
  end
  task :m => :menu
end

desc "sunum menüsü"
task :p => ["p:menu"]
task :presentation => :p
