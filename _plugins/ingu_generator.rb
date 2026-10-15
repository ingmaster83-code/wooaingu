require 'json'

module Jekyll
  module IText
    module_function

    def hangul_tail?(s)
      c = s.to_s.strip.sub(/[\s\)\]\}\>'"”’.,!?~·\-]+\z/, '')[-1]
      !c.nil? && c.ord >= 0xAC00 && c.ord <= 0xD7A3
    end

    def batchim?(s)
      c = s.to_s.strip.sub(/[\s\)\]\}\>'"”’.,!?~·\-]+\z/, '')[-1]
      return false if c.nil?
      o = c.ord
      (o >= 0xAC00 && o <= 0xD7A3) ? ((o - 0xAC00) % 28 != 0) : false
    end

    def josa(word, with_b, without_b)
      return "#{word}#{with_b}(#{without_b})" unless hangul_tail?(word)
      word.to_s + (batchim?(word) ? with_b : without_b)
    end

    def eun_neun(w); josa(w, '은', '는'); end

    def fmt(n)
      n.to_i.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
    end

    def pct(v, d = 1)
      return '-' if v.nil?
      format("%.#{d}f%%", v)
    end

    def spct(v, d = 1)
      return '-' if v.nil?
      v = 0.0 if v.abs < 0.5 * 10**-d
      v >= 0 ? "+#{format("%.#{d}f", v)}%" : "#{format("%.#{d}f", v)}%"
    end

    def i_ga(w); josa(w, '이', '가'); end

    def sdiff(n)
      return '-' if n.nil?
      n >= 0 ? "+#{fmt(n)}명" : "-#{fmt(n.abs)}명"
    end

    def ymlabel(ym)
      "#{ym[0, 4]}년 #{ym[4, 2].to_i}월"
    end

    def ymshort(ym)
      "#{ym[0, 4]}.#{ym[4, 2]}"
    end

    def month_add(ym, n)
      t = ym[0, 4].to_i * 12 + ym[4, 2].to_i - 1 + n
      format('%04d%02d', t / 12, t % 12 + 1)
    end

    def city_of(sg)
      sg.to_s.include?(' ') ? sg.split(' ').first : nil
    end
  end

  class InguGenerator < Generator
    safe true
    priority :normal

    BUCKETS = ['9세 이하', '10대', '20대', '30대', '40대', '50대', '60대', '70대', '80세 이상', '65세 이상'].freeze
    AGE_SLUG = %w[kids teens 20s 30s 40s 50s 60s 70s 80plus senior].freeze
    AGE_NAME = ['9세 이하 어린이', '10대 청소년', '20대', '30대', '40대', '50대', '60대', '70대', '80세 이상 초고령', '65세 이상 고령'].freeze
    A5_LABELS = ((0..19).map { |i| "#{i * 5}~#{i * 5 + 4}세" } + ['100세 이상']).freeze
    ONE_LABELS = ['19세 이하', '20대', '30대', '40대', '50대', '60대', '70대', '80세 이상'].freeze
    RANK_DONG = 100
    RANK_DO = 50
    RANK_SG = 100

    KINDS = {
      'pop' => { title: '인구가 많은 동네', sort: ->(r) { -r['tot'] }, min: ->(r) { true }, cols: ['인구', '세대수', '세대당 인구'], desc: '주민등록 인구가 많은 순서' },
      'single' => { title: '1인 가구 비율이 높은 동네', sort: ->(r) { -(r['r1'] || -1) }, min: ->(r) { r['hh'] && r['hh'] >= 1000 }, cols: ['1인 가구 비율', '1인 가구', '세대수'], desc: '세대수 1,000 이상 동네 중 1인 가구 비율이 높은 순서' },
      'old' => { title: '65세 이상 고령 인구 비율이 높은 동네', sort: ->(r) { -r['r65'] }, min: ->(r) { r['tot'] >= 1000 }, cols: ['65세 이상 비율', '65세 이상 인구', '인구'], desc: '인구 1,000명 이상 동네 중 65세 이상 비율이 높은 순서' },
      'young' => { title: '20·30대 인구 비율이 높은 동네', sort: ->(r) { -r['r2039'] }, min: ->(r) { r['tot'] >= 3000 }, cols: ['20·30대 비율', '20·30대 인구', '인구'], desc: '인구 3,000명 이상 동네 중 20·30대 비율이 높은 순서' },
      'kids' => { title: '14세 이하 아이가 많은 동네', sort: ->(r) { -r['r014'] }, min: ->(r) { r['tot'] >= 3000 }, cols: ['14세 이하 비율', '14세 이하 인구', '인구'], desc: '인구 3,000명 이상 동네 중 14세 이하 유소년 비율이 높은 순서' },
      'avglow' => { title: '평균 연령이 낮은 동네', sort: ->(r) { r['avg'] }, min: ->(r) { r['tot'] >= 3000 }, cols: ['평균 연령', '중위 연령', '인구'], desc: '인구 3,000명 이상 동네 중 평균 연령이 낮은 순서' },
      'avghigh' => { title: '평균 연령이 높은 동네', sort: ->(r) { -r['avg'] }, min: ->(r) { r['tot'] >= 1000 }, cols: ['평균 연령', '중위 연령', '인구'], desc: '인구 1,000명 이상 동네 중 평균 연령이 높은 순서' },
      'grow' => { title: '최근 1년 인구가 많이 늘어난 동네', sort: ->(r) { -(r['g12'] || -999) }, min: ->(r) { r['g12'] && r['p12'] >= 3000 }, cols: ['1년 증감률', '1년 증감', '인구'], desc: '1년 전 인구 3,000명 이상 동네 중 증가율이 높은 순서' },
      'shrink' => { title: '최근 1년 인구가 많이 줄어든 동네', sort: ->(r) { (r['g12'] || 999) }, min: ->(r) { r['g12'] && r['p12'] >= 3000 }, cols: ['1년 증감률', '1년 증감', '인구'], desc: '1년 전 인구 3,000명 이상 동네 중 감소율이 큰 순서' }
    }.freeze

    SG_KINDS = {
      'sg-pop' => { title: '인구가 많은 시군구', sort: ->(s) { -s['tot'] }, cols: ['인구', '세대수', '동네 수'], desc: '주민등록 인구가 많은 시군구 순서' },
      'sg-old' => { title: '고령 인구 비율이 높은 시군구', sort: ->(s) { -s['r65'] }, cols: ['65세 이상 비율', '65세 이상 인구', '인구'], desc: '65세 이상 인구 비율이 높은 시군구 순서' },
      'sg-grow' => { title: '최근 1년 인구가 늘어난 시군구', sort: ->(s) { -(s['g12'] || -999) }, cols: ['1년 증감률', '1년 증감', '인구'], desc: '최근 1년 인구 증가율이 높은 시군구 순서' },
      'sg-single' => { title: '1인 가구 비율이 높은 시군구', sort: ->(s) { -(s['r1'] || -1) }, cols: ['1인 가구 비율', '1인 가구', '세대수'], desc: '1인 가구 비율이 높은 시군구 순서' }
    }.freeze

    def generate(site)
      dir = File.join(site.source, '_rawdata')
      meta = JSON.parse(File.read(File.join(dir, 'ingu_meta.json'), encoding: 'utf-8'))
      dongs = JSON.parse(File.read(File.join(dir, 'ingu_dong.json'), encoding: 'utf-8'))
      beops = JSON.parse(File.read(File.join(dir, 'ingu_beop.json'), encoding: 'utf-8'))
      ym = meta['ym']
      ym12 = IText.month_add(ym, -12)
      ym3 = IText.month_add(ym, -3)
      ym1 = IText.month_add(ym, -1)
      ym36 = IText.month_add(ym, -36)

      dongs.each { |r| InguGenerator.derive(r, ym1, ym3, ym12, ym36) }
      groups_sg = dongs.group_by { |r| [r['do'], r['sg']] }
      groups_do = dongs.group_by { |r| r['do'] }
      groups_city = dongs.select { |r| IText.city_of(r['sg']) }.group_by { |r| [r['do'], IText.city_of(r['sg'])] }

      # 순위(시군구 내·시도 내·전국)
      by_nat = dongs.sort_by { |r| [-r['tot'], r['id']] }
      by_nat.each_with_index { |r, i| r['rk_nat'] = i + 1 }
      groups_do.each_value { |l| l.sort_by { |r| [-r['tot'], r['id']] }.each_with_index { |r, i| r['rk_do'] = i + 1; r['n_do'] = l.size } }
      groups_sg.each_value do |l|
        l.sort_by { |r| [-r['tot'], r['id']] }.each_with_index { |r, i| r['rk_sg'] = i + 1; r['n_sg'] = l.size }
        l.select { |r| r['r1'] }.sort_by { |r| -r['r1'] }.each_with_index { |r, i| r['rk1_sg'] = i + 1; r['n1_sg'] = l.count { |x| x['r1'] } }
        l.sort_by { |r| -r['r65'] }.each_with_index { |r, i| r['rk65_sg'] = i + 1 }
      end

      counts = Hash.new(0)
      sg_stats = {}
      groups_sg.each { |(d, s), l| sg_stats[[d, s]] = InguGenerator.agg(s, l) }
      city_stats = {}
      groups_city.each { |(d, c), l| city_stats[[d, c]] = InguGenerator.agg(c, l) }
      do_stats = {}
      groups_do.each { |d, l| do_stats[d] = InguGenerator.agg(d, l) }

      # 행정동 페이지
      dongs.each do |r|
        nb = groups_sg[[r['do'], r['sg']]].reject { |x| x['id'] == r['id'] }.sort_by { |x| -x['tot'] }.first(12)
        site.pages << DongPage.new(site, r, nb, meta)
        counts[:dong] += 1
      end

      # 법정동 페이지(행정동과 이름이 다른 법정동)
      dong_idx = dongs.group_by { |r| [r['do'], r['sg'], r['dong']] }
      beops.each do |b|
        kids = (b['dongs'] || []).map { |n| (dong_idx[[b['do'], b['sg'], n]] || []).first }.compact
        site.pages << BeopPage.new(site, b, kids, meta)
        counts[:beop] += 1
      end

      # 시군구·시(구가 있는 시) 페이지
      groups_sg.each do |(d, s), l|
        site.pages << SgPage.new(site, d, s, sg_stats[[d, s]], l, meta)
        counts[:sg] += 1
      end
      groups_city.each do |(d, c), l|
        gus = l.group_by { |r| r['sg'] }.map { |s, ll| sg_stats[[d, s]].merge('sg' => s) }.sort_by { |x| -x['tot'] }
        site.pages << CityPage.new(site, d, c, city_stats[[d, c]], gus, l, meta)
        counts[:city] += 1
      end

      # 시군구·시 × 연령대 페이지
      nat_tot = dongs.sum { |r| r['tot'] }.to_f
      nat_grp = (0..9).map { |i| dongs.sum { |r| InguGenerator.grp(r, i)[0] } }
      sg_share_rank = (0..9).map { |i| sg_stats.sort_by { |_, v| -InguGenerator.grp(v, i)[0].to_f / v['tot'] }.each_with_index.to_h { |(k, _), idx| [k, idx + 1] } }
      groups_sg.each do |(d, s), l|
        (0..9).each do |i|
          site.pages << AgePage.new(site, d, s, sg_stats[[d, s]], l, i, nat_grp, nat_tot, sg_share_rank[i][[d, s]], sg_stats.size, meta)
          counts[:age] += 1
        end
      end
      groups_city.each do |(d, c), l|
        (0..9).each do |i|
          site.pages << AgePage.new(site, d, c, city_stats[[d, c]], l, i, nat_grp, nat_tot, nil, nil, meta)
          counts[:age] += 1
        end
      end

      # 시도 페이지
      sgs_by_do = Hash.new { |h, k| h[k] = [] }
      groups_sg.each_key { |d, s| sgs_by_do[d] << s }
      groups_do.each do |d, l|
        rows = sgs_by_do[d].map { |s| sg_stats[[d, s]].merge('sg' => s) }
        city_seen = {}
        merged = []
        rows.sort_by { |x| -x['tot'] }.each do |x|
          c = IText.city_of(x['sg'])
          if c
            next if city_seen[c]
            city_seen[c] = true
            merged << city_stats[[d, c]].merge('sg' => c, 'city' => true)
          else
            merged << x
          end
        end
        site.pages << DoPage.new(site, d, do_stats[d], merged.sort_by { |x| -x['tot'] }, l, meta)
        counts[:do] += 1
      end

      # 랭킹
      do_names = groups_do.keys.sort
      KINDS.each do |k, spec|
        pool = dongs.select { |r| spec[:min].call(r) }
        site.pages << RankPage.new(site, k, spec, nil, pool.sort_by { |r| [spec[:sort].call(r), r['id']] }.first(RANK_DONG), meta)
        counts[:rank] += 1
        do_names.each do |d|
          rows = pool.select { |r| r['do'] == d }.sort_by { |r| [spec[:sort].call(r), r['id']] }.first(RANK_DO)
          next if rows.size < 5
          site.pages << RankPage.new(site, k, spec, d, rows, meta)
          counts[:rank] += 1
        end
      end
      all_sg = sg_stats.map { |(d, s), v| v.merge('sg' => s, 'do' => d) } + city_stats.map { |(d, c), v| v.merge('sg' => c, 'do' => d, 'city' => true) }
      SG_KINDS.each do |k, spec|
        rows = all_sg.sort_by { |s| [spec[:sort].call(s), s['do'], s['sg']] }.first(RANK_SG)
        site.pages << SgRankPage.new(site, k, spec, rows, meta)
        counts[:rank] += 1
      end
      site.pages << RankIndexPage.new(site, KINDS.map { |k, v| [k, v[:title]] }, SG_KINDS.map { |k, v| [k, v[:title]] }, do_names, meta)

      # 홈·지역 인덱스용 통계
      tot = meta['tot']
      hh = meta['hh']
      avg_all = dongs.sum { |r| r['avg'] * r['tot'] } / nat_tot
      site.data['ingu_stats'] = {
        'ym' => IText.ymlabel(ym), 'ymshort' => IText.ymshort(ym), 'tot' => IText.fmt(tot), 'hh' => IText.fmt(hh), 'dongs' => IText.fmt(meta['dongs']),
        'hhn' => hh.positive? ? format('%.2f', meta['pop_hh'].to_f / hh) : '-', 'r1' => hh.positive? ? IText.pct(meta['h1'].to_f / hh * 100) : '-',
        'r65' => IText.pct(meta['old65'].to_f / tot * 100), 'avg' => format('%.1f', avg_all), 'sgs' => IText.fmt(sg_stats.size),
        'do_rows' => do_names.map { |d| s = do_stats[d]; { 'name' => d, 'tot' => IText.fmt(s['tot']), 'tot_n' => s['tot'], 'g12' => IText.spct(s['g12']), 'r65' => IText.pct(s['r65']), 'sgs' => groups_do[d].map { |r| r['sg'] }.uniq.size } }.sort_by { |x| -x['tot_n'] },
        'top' => by_nat.first(12).map { |r| InguGenerator.row(r) },
        'old' => dongs.select { |r| r['tot'] >= 1000 }.sort_by { |r| -r['r65'] }.first(8).map { |r| InguGenerator.row(r) },
        'young' => dongs.select { |r| r['tot'] >= 3000 }.sort_by { |r| -r['r2039'] }.first(8).map { |r| InguGenerator.row(r) },
        'single' => dongs.select { |r| r['hh'] && r['hh'] >= 1000 }.sort_by { |r| -r['r1'] }.first(8).map { |r| InguGenerator.row(r) },
        'sg_top' => all_sg.sort_by { |s| -s['tot'] }.first(10).map { |s| { 'name' => s['sg'], 'loc' => s['do'], 'tot' => IText.fmt(s['tot']), 'url' => InguGenerator.sg_url(s['do'], s['sg'], s['city']) } }
      }

      # 검색 색인
      idx = []
      dongs.each { |r| idx << { 'n' => r['dong'], 't' => '동네', 'l' => "#{r['do']} #{r['sg']}", 'u' => InguGenerator.dong_url(r) } }
      beops.each { |b| idx << { 'n' => b['name'], 't' => '법정동', 'l' => "#{b['do']} #{b['sg']}", 'u' => InguGenerator.beop_url(b) } }
      sg_stats.each_key { |d, s| idx << { 'n' => s, 't' => '시군구', 'l' => d, 'u' => InguGenerator.sg_url(d, s, false) } }
      city_stats.each_key { |d, c| idx << { 'n' => c, 't' => '시', 'l' => d, 'u' => InguGenerator.sg_url(d, c, true) } }
      pg = PageWithoutAFile.new(site, site.source, '', 'search_index.json')
      pg.content = JSON.generate(idx)
      pg.data['layout'] = nil
      pg.data['sitemap'] = false
      site.pages << pg
      Jekyll.logger.info 'InguGenerator:', "행정동 #{counts[:dong]} / 법정동 #{counts[:beop]} / 시군구 #{counts[:sg]} / 시 #{counts[:city]} / 연령대 #{counts[:age]} / 시도 #{counts[:do]} / 랭킹 #{counts[:rank] + 1}"
    end

    # ── 파생 지표 ───────────────────────────────────────
    def self.derive(r, ym1, ym3, ym12, ym36)
      tot = r['tot'].to_f
      r['r65'] = r['old65'] / tot * 100
      r['r014'] = r['kid14'] / tot * 100
      r['r1564'] = 100 - r['r65'] - r['r014']
      r['r2039'] = (r['ag'][2] + r['ag'][3]) / tot * 100
      r['r9'] = r['ag'][0] / tot * 100
      r['aging'] = r['kid14'].positive? ? r['old65'].to_f / r['kid14'] * 100 : nil
      work = tot - r['old65'] - r['kid14']
      r['dep'] = work.positive? ? (r['old65'] + r['kid14']) / work * 100 : nil
      r['sexr'] = r['fem'].positive? ? (r['male'].to_f / r['fem'] * 100) : nil
      if r['hh'] && r['hh'].positive?
        r['h1'] = r['hs'][0]
        r['r1'] = r['h1'].to_f / r['hh'] * 100
        r['hhn'] = tot / r['hh']
      end
      trh = (r['tr'] + r['yr']).to_h { |x| [x[0], x] }
      { 'p1' => ym1, 'p3' => ym3, 'p12' => ym12, 'p36' => ym36 }.each do |k, m|
        v = trh[m] && trh[m][1]
        r[k] = v
        r['g' + k[1..]] = v && v.positive? ? ((tot - v) / v * 100) : nil
      end
      r['d12'] = r['p12'] ? r['tot'] - r['p12'] : nil
      r['d1'] = r['p1'] ? r['tot'] - r['p1'] : nil
      r['d3'] = r['p3'] ? r['tot'] - r['p3'] : nil
      r['d36'] = r['p36'] ? r['tot'] - r['p36'] : nil
      top = r['ag'][0, 9].each_with_index.max_by { |v, _| v }
      r['topb'] = top[1]
      r['topr'] = top[0] / tot * 100
    end

    # 연령 묶음 i(0~8: 10세 단위, 9: 65세 이상) → [인구, 남자, 여자]
    def self.grp(r, i)
      if i == 9
        m = r['a5m'][13..].sum
        f = r['a5f'][13..].sum
        [m + f, m, f]
      else
        [r['ag'][i], r['agm'][i], r['agf'][i]]
      end
    end

    # 동 묶음 → 시군구·시도 집계
    def self.agg(name, ds)
      tot = ds.sum { |d| d['tot'] }
      withh = ds.select { |d| d['hh'] }
      hh = withh.sum { |d| d['hh'] }
      pop_hh = withh.sum { |d| d['tot'] }
      h1 = withh.sum { |d| d['hs'][0] }
      old = ds.sum { |d| d['old65'] }
      kid = ds.sum { |d| d['kid14'] }
      both = ds.select { |d| d['p12'] }
      cur = both.sum { |d| d['tot'] }
      prev = both.sum { |d| d['p12'] }
      g12 = prev.positive? ? ((cur - prev).to_f / prev * 100) : nil
      {
        'name' => name, 'tot' => tot, 'hh' => hh, 'dongs' => ds.size, 'old' => old, 'old65' => old, 'kid14' => kid,
        'male' => ds.sum { |d| d['male'] }, 'fem' => ds.sum { |d| d['fem'] },
        'ag' => (0..8).map { |i| ds.sum { |d| d['ag'][i] } }, 'agm' => (0..8).map { |i| ds.sum { |d| d['agm'][i] } }, 'agf' => (0..8).map { |i| ds.sum { |d| d['agf'][i] } },
        'a5m' => (0..20).map { |i| ds.sum { |d| d['a5m'][i] } }, 'a5f' => (0..20).map { |i| ds.sum { |d| d['a5f'][i] } },
        'r65' => old.to_f / tot * 100, 'r014' => kid.to_f / tot * 100, 'r1' => hh.positive? ? (h1.to_f / hh * 100) : nil, 'h1' => h1,
        'hhn' => hh.positive? ? (pop_hh.to_f / hh) : nil, 'g12' => g12, 'd12' => prev.positive? ? cur - prev : nil,
        'avg' => ds.sum { |d| d['avg'] * d['tot'] } / tot.to_f
      }
    end

    def self.q(s)
      URI.encode_www_form_component(s.to_s).gsub('+', '%20')
    end

    def self.dong_url(r)
      "/dong/#{q(r['do'])}/#{q(r['sg'])}/#{q(r['dong'])}/"
    end

    def self.beop_url(b)
      "/beop/#{q(b['do'])}/#{q(b['sg'])}/#{q(b['name'])}/"
    end

    def self.sg_url(d, s, city)
      "/region/#{q(d)}/#{q(s)}/"
    end

    def self.row(r)
      {
        'name' => r['dong'], 'url' => dong_url(r), 'loc' => "#{r['do']} #{r['sg']}", 'tot' => IText.fmt(r['tot']), 'hh' => r['hh'] ? IText.fmt(r['hh']) : '-',
        'r65' => IText.pct(r['r65']), 'r2039' => IText.pct(r['r2039']), 'r1' => IText.pct(r['r1']), 'g12' => IText.spct(r['g12']), 'avg' => format('%.1f', r['avg'])
      }
    end
  end

  class IBasePage < Page
    def setup(site, dir, layout)
      @site = site
      @base = site.source
      @dir = dir
      @name = 'index.html'
      process(@name)
      read_yaml(File.join(@base, '_layouts'), "#{layout}.html")
      data['layout'] = layout
    end

    def seo(title, desc)
      data['title'] = title
      data['description'] = desc[0, 155]
    end

    def faq(pairs)
      data['faq'] = pairs.map { |q, a| { 'q' => q, 'a' => a } }
    end

    def f(n)
      IText.fmt(n)
    end

    # 10세 단위 연령 구성 표(남·여·합계·비중)
    def age_rows(ag, agm, agf)
      tot = ag.sum.to_f
      mx = ag.max.to_f
      ag.each_index.map do |i|
        { 'label' => InguGenerator::BUCKETS[i], 'male' => f(agm[i]), 'fem' => f(agf[i]), 'n' => f(ag[i]), 'share' => IText.pct(ag[i] / tot * 100), 'w' => (ag[i] / mx * 100).round }
      end
    end

    # 5세 단위 연령 구성 표
    def a5_rows(am, af)
      tot = (am.sum + af.sum).to_f
      tots = am.each_index.map { |i| am[i] + af[i] }
      mx = tots.max.to_f
      tots.each_index.map do |i|
        { 'label' => InguGenerator::A5_LABELS[i], 'male' => f(am[i]), 'fem' => f(af[i]), 'n' => f(tots[i]), 'share' => IText.pct(tots[i] / tot * 100), 'w' => mx.positive? ? (tots[i] / mx * 100).round : 0 }
      end
    end

    # 월별 추이 표(최신 월부터)
    def trend_rows(tr)
      rows = []
      mx = (tr.map { |x| x[1] }.max || 1).to_f
      tr.each_with_index do |x, i|
        ym, v = x[0], x[1]
        prev = i.positive? ? tr[i - 1][1] : nil
        d = prev ? v - prev : nil
        rows << { 'ym' => IText.ymlabel(ym), 'n' => f(v), 'd' => d.nil? ? '-' : IText.sdiff(d), 'up' => d.nil? || d >= 0, 'w' => (v / mx * 100).round }
      end
      rows.reverse
    end

    # 같은 달 기준 연도별 표(인구·세대수·1인 가구·65세 이상)
    def year_rows(yr)
      rows = []
      yr.each_with_index do |x, i|
        ym, tot, hh, h1, old = x[0], x[1], x[2], x[3], x[4]
        prev = i.positive? ? yr[i - 1][1] : nil
        pc = prev && prev.positive? ? (tot - prev).to_f / prev * 100 : nil
        rows << { 'ym' => IText.ymlabel(ym), 'n' => f(tot), 'chg' => pc.nil? ? '-' : IText.spct(pc), 'up' => pc.nil? || pc >= 0,
                  'hh' => hh.to_i.positive? ? f(hh) : '-', 'r1' => hh.to_i.positive? ? IText.pct(h1.to_f / hh * 100) : '-', 'r65' => IText.pct(old.to_f / tot * 100) }
      end
      rows.reverse
    end

    def size_rows(r)
      return [] unless r['hh']
      hh = r['hh'].to_f
      [['1인 가구', r['hs'][0]], ['2인 가구', r['hs'][1]], ['3인 가구', r['hs'][2]], ['4인 가구', r['hs'][3]], ['5인 이상 가구', r['hs'][4]]].map do |label, c|
        { 'label' => label, 'n' => f(c), 'share' => IText.pct(c / hh * 100), 'w' => (c / hh * 100).round }
      end
    end

    def one_rows(r)
      return [] unless r['o8']
      tot = r['o8'].sum.to_f
      return [] unless tot.positive?
      mx = r['o8'].max.to_f
      r['o8'].each_index.map do |i|
        { 'label' => InguGenerator::ONE_LABELS[i], 'n' => f(r['o8'][i]), 'fem' => f(r['o8f'][i]), 'share' => IText.pct(r['o8'][i] / tot * 100), 'w' => (r['o8'][i] / mx * 100).round }
      end
    end

    def grp3_rows(tot, kid, old)
      work = tot - kid - old
      [['유소년(0~14세)', kid], ['생산연령(15~64세)', work], ['고령(65세 이상)', old]].map do |label, c|
        { 'label' => label, 'n' => f(c), 'share' => IText.pct(c.to_f / tot * 100), 'w' => (c.to_f / tot * 100).round }
      end
    end
  end

  # ── 행정동 ─────────────────────────────────────────
  class DongPage < IBasePage
    def initialize(site, r, neighbors, meta)
      setup(site, "dong/#{r['do']}/#{r['sg']}/#{r['dong']}", 'dong')
      ym = meta['ym']
      yl = IText.ymlabel(ym)
      name = r['dong']
      loc = "#{r['do']} #{r['sg']}"
      data['doShort'] = r['do']
      data['sigungu'] = r['sg']
      data['dong'] = name
      data['city'] = IText.city_of(r['sg'])
      data['ym'] = yl
      data['tot'] = f(r['tot'])
      data['male'] = f(r['male'])
      data['fem'] = f(r['fem'])
      data['sexr'] = r['sexr'] ? format('%.1f', r['sexr']) : '-'
      data['hasHh'] = !r['hh'].nil?
      data['hh'] = r['hh'] ? f(r['hh']) : '-'
      data['hhn'] = r['hhn'] ? format('%.2f', r['hhn']) : '-'
      data['r1'] = IText.pct(r['r1'])
      data['r65'] = IText.pct(r['r65'])
      data['old65'] = f(r['old65'])
      data['kid14'] = f(r['kid14'])
      data['r014'] = IText.pct(r['r014'])
      data['r1564'] = IText.pct(r['r1564'])
      data['aging'] = r['aging'] ? format('%.1f', r['aging']) : '-'
      data['dep'] = r['dep'] ? format('%.1f', r['dep']) : '-'
      data['avg'] = format('%.1f', r['avg'])
      data['med'] = r['med']
      data['r2039'] = IText.pct(r['r2039'])
      data['r9'] = IText.pct(r['r9'])
      data['g12'] = IText.spct(r['g12'])
      data['d12'] = r['d12'].nil? ? '-' : IText.sdiff(r['d12'])
      data['up12'] = r['d12'].nil? || r['d12'] >= 0
      data['g1'] = IText.spct(r['g1'], 2)
      data['d1'] = r['d1'].nil? ? '-' : IText.sdiff(r['d1'])
      data['has12'] = !r['g12'].nil?
      data['ageRows'] = age_rows(r['ag'][0, 9], r['agm'], r['agf'])
      data['a5Rows'] = a5_rows(r['a5m'], r['a5f'])
      data['grp3'] = grp3_rows(r['tot'], r['kid14'], r['old65'])
      data['sizeRows'] = size_rows(r)
      data['oneRows'] = one_rows(r)
      data['hasOne'] = !data['oneRows'].empty?
      data['trRows'] = trend_rows(r['tr'])
      data['trCount'] = r['tr'].size
      data['yrRows'] = year_rows(r['yr'])
      data['yrCount'] = r['yr'].size
      data['ri'] = (r['ri'] || []).first(60).map { |n, t, h| { 'name' => n, 'tot' => f(t), 'hh' => f(h), 'hhn' => h.positive? ? format('%.2f', t.to_f / h) : '-' } }
      data['riCount'] = (r['ri'] || []).size
      data['rkSg'] = r['rk_sg']
      data['nSg'] = r['n_sg']
      data['rkNat'] = r['rk_nat']
      data['rk65Sg'] = r['rk65_sg']
      data['neighbors'] = neighbors.map { |x| { 'name' => x['dong'], 'url' => InguGenerator.dong_url(x), 'tot' => f(x['tot']), 'r65' => IText.pct(x['r65']) } }
      data['sgUrl'] = InguGenerator.sg_url(r['do'], r['sg'], false)
      data['cityUrl'] = data['city'] ? InguGenerator.sg_url(r['do'], data['city'], true) : nil
      data['topAgeLabel'] = InguGenerator::BUCKETS[r['topb']]
      data['topAgeShare'] = IText.pct(r['topr'])
      data['sgLinks'] = { 'apt' => "https://wooaapt.wooahouse.com/region/#{InguGenerator.q(r['do'])}/#{InguGenerator.q(r['sg'])}/", 'biz' => "https://wooasanggwon.wooahouse.com/sg/#{InguGenerator.q(r['do'])}/#{InguGenerator.q(r['sg'])}/" }

      s = +"#{loc} #{IText.eun_neun(name)} #{yl} 기준 주민등록 인구가 #{f(r['tot'])}명(남자 #{f(r['male'])}명, 여자 #{f(r['fem'])}명)입니다. "
      s << "세대수는 #{f(r['hh'])}세대로 세대당 평균 #{format('%.2f', r['hhn'])}명이며, 1인 가구가 #{IText.pct(r['r1'])}를 차지합니다. " if r['hh']
      s << "평균 연령은 #{format('%.1f', r['avg'])}세(중위 연령 #{r['med']}세)이고, 65세 이상 고령 인구는 #{f(r['old65'])}명(#{IText.pct(r['r65'])}), 14세 이하는 #{IText.pct(r['r014'])}, 20·30대는 #{IText.pct(r['r2039'])}입니다. "
      s << "10세 단위로는 #{IText.i_ga(InguGenerator::BUCKETS[r['topb']])} #{IText.pct(r['topr'])}로 가장 많습니다. "
      s << "#{r['sg']} #{r['n_sg']}개 동네 중 인구 #{r['rk_sg']}위, 전국 #{f(meta['dongs'])}개 읍면동 중 #{f(r['rk_nat'])}위입니다. "
      if r['g12']
        s << "#{IText.ymlabel(IText.month_add(ym, -12))} 대비 1년간 인구는 #{IText.sdiff(r['d12'])}(#{IText.spct(r['g12'])}) #{r['d12'] >= 0 ? '늘었습니다' : '줄었습니다'}."
        s << " 3년 전(#{IText.ymlabel(IText.month_add(ym, -36))})보다는 #{IText.sdiff(r['d36'])}(#{IText.spct(r['g36'])}) #{r['d36'] >= 0 ? '늘었습니다' : '줄었습니다'}." if r['g36']
      end
      data['summary'] = s

      seo("#{loc} #{name} 인구·세대수 - 연령별·1인가구·고령화 (#{IText.ymshort(ym)})",
          "#{loc} #{name} 인구 #{f(r['tot'])}명#{r['hh'] ? ", 세대수 #{f(r['hh'])}세대, 1인 가구 #{IText.pct(r['r1'])}" : ''}, 65세 이상 #{IText.pct(r['r65'])}, 평균 연령 #{format('%.1f', r['avg'])}세. 연령별 인구와 최근 인구 추이.")
      pairs = []
      pairs << ["#{name} 인구는 몇 명인가요?", "#{yl} 말일 기준 #{loc} #{name}의 주민등록 인구는 #{f(r['tot'])}명입니다. 남자 #{f(r['male'])}명, 여자 #{f(r['fem'])}명#{r['sexr'] ? "(여자 100명당 남자 #{format('%.1f', r['sexr'])}명)" : ''}입니다. 실제로 거주하는 인구와는 차이가 있을 수 있습니다."]
      if r['hh']
        pairs << ["#{name} 세대수와 1인 가구 비율은 얼마인가요?", "#{name}의 세대수는 #{f(r['hh'])}세대이고 세대당 평균 인구는 #{format('%.2f', r['hhn'])}명입니다. 1인 가구는 #{f(r['h1'])}세대로 전체의 #{IText.pct(r['r1'])}이며, #{r['rk1_sg'] ? (r['rk1_sg'] == 1 ? "#{r['sg']}에서 1인 가구 비율이 가장 높습니다." : "#{r['sg']}에서 1인 가구 비율이 #{r['rk1_sg']}번째로 높습니다.") : ''}"]
      end
      pairs << ["#{name}의 고령 인구(65세 이상) 비율과 평균 연령은?", "65세 이상 인구는 #{f(r['old65'])}명으로 전체의 #{IText.pct(r['r65'])}이고, 평균 연령은 #{format('%.1f', r['avg'])}세, 중위 연령은 #{r['med']}세입니다. #{r['sg']} 안에서 고령 인구 비율은 #{r['rk65_sg'] == 1 ? '가장 높습니다' : "#{r['rk65_sg']}번째로 높습니다"}."]
      pairs << ["#{name}에서 가장 많은 연령대는 무엇인가요?", "10세 단위로 #{IText.i_ga(InguGenerator::BUCKETS[r['topb']])} #{f(r['ag'][r['topb']])}명(#{IText.pct(r['topr'])})으로 가장 많습니다. 14세 이하는 #{IText.pct(r['r014'])}, 20·30대는 #{IText.pct(r['r2039'])}입니다."]
      pairs << ['주민등록 인구와 실제 거주 인구는 왜 다른가요?', '주민등록 인구는 주민등록상 주소지 기준이라 대학·직장 때문에 다른 곳에 사는 사람, 거주불명자, 재외국민이 함께 집계됩니다. 통계청 인구총조사는 실제 거주지 기준이라 수치가 다를 수 있습니다.']
      faq(pairs)
    end
  end

  # ── 법정동 ─────────────────────────────────────────
  class BeopPage < IBasePage
    def initialize(site, b, kids, meta)
      setup(site, "beop/#{b['do']}/#{b['sg']}/#{b['name']}", 'beop')
      ym = b['ym'] || meta['ym']
      yl = IText.ymlabel(ym)
      name = b['name']
      loc = "#{b['do']} #{b['sg']}"
      hhn = b['hh'].positive? ? b['tot'].to_f / b['hh'] : nil
      tr = b['tr'].map { |m, t, _| [m, t] }
      cur = b['tr'].to_h { |m, t, h| [m, [t, h]] }
      p12 = cur[IText.month_add(ym, -12)]
      data['doShort'] = b['do']
      data['sigungu'] = b['sg']
      data['bName'] = name
      data['ym'] = yl
      data['tot'] = f(b['tot'])
      data['male'] = f(b['male'])
      data['fem'] = f(b['fem'])
      data['hh'] = f(b['hh'])
      data['hhn'] = hhn ? format('%.2f', hhn) : '-'
      data['trRows'] = trend_rows(tr)
      data['trCount'] = tr.size
      data['kids'] = kids.map { |x| { 'name' => x['dong'], 'url' => InguGenerator.dong_url(x), 'tot' => f(x['tot']), 'hh' => x['hh'] ? f(x['hh']) : '-', 'r65' => IText.pct(x['r65']), 'r1' => IText.pct(x['r1']) } }
      data['hasKids'] = !kids.empty?
      data['sgUrl'] = InguGenerator.sg_url(b['do'], b['sg'], false)
      data['has12'] = !p12.nil?
      data['d12'] = p12 ? IText.sdiff(b['tot'] - p12[0]) : '-'
      data['g12'] = p12 && p12[0].positive? ? IText.spct((b['tot'] - p12[0]).to_f / p12[0] * 100) : '-'
      data['up12'] = p12.nil? || b['tot'] >= p12[0]

      s = +"#{loc} #{IText.eun_neun(name)} #{yl} 기준 주민등록 인구가 #{f(b['tot'])}명(남자 #{f(b['male'])}명, 여자 #{f(b['fem'])}명), 세대수가 #{f(b['hh'])}세대입니다. "
      s << "세대당 평균 인구는 #{format('%.2f', hhn)}명입니다. " if hhn
      s << "#{name}은(는) 법정동 이름이며, 행정동 #{kids.map { |x| x['dong'] }.join('·')}에 걸쳐 있습니다. 연령별 인구와 1인 가구 비율은 아래 행정동 페이지에서 확인하세요. " unless kids.empty?
      s << "#{IText.ymlabel(IText.month_add(ym, -12))} 대비 1년간 인구는 #{IText.sdiff(b['tot'] - p12[0])}(#{data['g12']}) #{b['tot'] >= p12[0] ? '늘었습니다' : '줄었습니다'}." if p12
      data['summary'] = s

      seo("#{loc} #{name} 인구·세대수 (#{IText.ymshort(ym)}, 법정동 기준)", "#{loc} #{name} 인구 #{f(b['tot'])}명, 세대수 #{f(b['hh'])}세대#{hhn ? ", 세대당 #{format('%.2f', hhn)}명" : ''}. 법정동 기준 주민등록 인구와 최근 #{tr.size}개월 추이.")
      faq([["#{name} 인구는 몇 명인가요?", "#{yl} 말일 기준 #{loc} #{name}의 주민등록 인구는 #{f(b['tot'])}명, 세대수는 #{f(b['hh'])}세대입니다."],
           ['법정동 인구와 행정동 인구는 왜 다른가요?', '법정동은 법으로 정한 주소상 동네 이름이고, 행정동은 주민센터가 관할하는 행정 구역입니다. 큰 법정동은 여러 행정동으로 나뉘고(예: 역삼동 → 역삼1동·역삼2동), 반대로 한 행정동이 여러 법정동을 묶기도 해서 인구가 서로 다르게 나옵니다.']])
    end
  end

  # ── 시군구·시·시도 ──────────────────────────────────
  class AreaBase < IBasePage
    def fill_common(st, ds, meta)
      ym = meta['ym']
      data['ym'] = IText.ymlabel(ym)
      data['tot'] = f(st['tot'])
      data['hh'] = st['hh'].positive? ? f(st['hh']) : '-'
      data['hhn'] = st['hhn'] ? format('%.2f', st['hhn']) : '-'
      data['r1'] = IText.pct(st['r1'])
      data['r65'] = IText.pct(st['r65'])
      data['r014'] = IText.pct(st['r014'])
      data['avg'] = format('%.1f', st['avg'])
      data['g12'] = IText.spct(st['g12'])
      data['d12'] = st['d12'].nil? ? '-' : IText.sdiff(st['d12'])
      data['up12'] = st['d12'].nil? || st['d12'] >= 0
      data['dongCount'] = st['dongs']
      data['ageRows'] = age_rows(st['ag'], st['agm'], st['agf'])
      data['grp3'] = grp3_rows(st['tot'], st['kid14'], st['old65'])
      data['male'] = f(st['male'])
      data['fem'] = f(st['fem'])
    end

    def dong_rows(ds)
      ds.sort_by { |x| -x['tot'] }.map do |x|
        { 'name' => x['dong'], 'url' => InguGenerator.dong_url(x), 'tot' => f(x['tot']), 'hh' => x['hh'] ? f(x['hh']) : '-', 'r65' => IText.pct(x['r65']), 'r1' => IText.pct(x['r1']), 'avg' => format('%.1f', x['avg']), 'g12' => IText.spct(x['g12']), 'up' => x['g12'].nil? || x['g12'] >= 0 }
      end
    end

    def area_rows(rows, do_name)
      rows.map do |x|
        { 'name' => x['sg'], 'url' => "/region/#{InguGenerator.q(do_name)}/#{InguGenerator.q(x['sg'])}/", 'tot' => f(x['tot']), 'hh' => x['hh'].positive? ? f(x['hh']) : '-', 'r65' => IText.pct(x['r65']), 'r1' => IText.pct(x['r1']), 'avg' => format('%.1f', x['avg']), 'g12' => IText.spct(x['g12']), 'up' => x['g12'].nil? || x['g12'] >= 0, 'dongs' => x['dongs'] }
      end
    end

    def age_links(d, s, st)
      (0..9).map { |j| n = InguGenerator.grp(st, j)[0]; { 'label' => InguGenerator::AGE_NAME[j], 'url' => "/age/#{InguGenerator.q(d)}/#{InguGenerator.q(s)}/#{InguGenerator::AGE_SLUG[j]}/", 'n' => f(n), 'share' => IText.pct(n.to_f / st['tot'] * 100) } }
    end

    def lists(ds)
      {
        'old' => ds.select { |x| x['tot'] >= 1000 }.sort_by { |x| -x['r65'] }.first(5),
        'young' => ds.select { |x| x['tot'] >= 3000 }.sort_by { |x| -x['r2039'] }.first(5),
        'single' => ds.select { |x| x['hh'] && x['hh'] >= 1000 }.sort_by { |x| -x['r1'] }.first(5)
      }
    end

    def mini(x, key)
      v = { 'old' => IText.pct(x['r65']), 'young' => IText.pct(x['r2039']), 'single' => IText.pct(x['r1']) }[key]
      { 'name' => x['dong'], 'url' => InguGenerator.dong_url(x), 'loc' => x['sg'], 'v' => v, 'tot' => f(x['tot']) }
    end
  end

  class AgePage < AreaBase
    def initialize(site, d, s, st, ds, i, nat_grp, nat_tot, rk, rk_n, meta)
      slug = InguGenerator::AGE_SLUG[i]
      setup(site, "age/#{d}/#{s}/#{slug}", 'age')
      lab = InguGenerator::BUCKETS[i]
      nm = InguGenerator::AGE_NAME[i]
      n, nm_m, nm_f = InguGenerator.grp(st, i)
      share = n.to_f / st['tot'] * 100
      nat_share = nat_grp[i] / nat_tot * 100
      diff = share - nat_share
      gv = ->(x) { InguGenerator.grp(x, i)[0] }
      data['doShort'] = d
      data['sigungu'] = s
      data['ym'] = IText.ymlabel(meta['ym'])
      data['label'] = lab
      data['ageName'] = nm
      data['n'] = f(n)
      data['male'] = f(nm_m)
      data['fem'] = f(nm_f)
      data['share'] = IText.pct(share)
      data['natShare'] = IText.pct(nat_share)
      data['diff'] = format('%+.1f%%p', diff)
      data['tot'] = f(st['tot'])
      data['sgUrl'] = InguGenerator.sg_url(d, s, false)
      data['rank'] = rk
      data['rankN'] = rk_n
      data['byCount'] = ds.sort_by { |x| -gv.call(x) }.first(15).map { |x| { 'name' => x['dong'], 'url' => InguGenerator.dong_url(x), 'n' => f(gv.call(x)), 'share' => IText.pct(gv.call(x).to_f / x['tot'] * 100), 'tot' => f(x['tot']) } }
      data['byShare'] = ds.select { |x| x['tot'] >= 1000 }.sort_by { |x| -gv.call(x).to_f / x['tot'] }.first(10).map { |x| { 'name' => x['dong'], 'url' => InguGenerator.dong_url(x), 'n' => f(gv.call(x)), 'share' => IText.pct(gv.call(x).to_f / x['tot'] * 100), 'tot' => f(x['tot']) } }
      data['others'] = (0..9).reject { |j| j == i }.map { |j| nj = InguGenerator.grp(st, j)[0]; { 'label' => InguGenerator::AGE_NAME[j], 'url' => "/age/#{InguGenerator.q(d)}/#{InguGenerator.q(s)}/#{InguGenerator::AGE_SLUG[j]}/", 'n' => f(nj), 'share' => IText.pct(nj.to_f / st['tot'] * 100) } }
      higher = diff >= 0
      sm = +"#{d} #{IText.eun_neun(s)} #{data['ym']} 기준 #{nm} 주민등록 인구가 #{f(n)}명(남자 #{f(nm_m)}명, 여자 #{f(nm_f)}명)으로 전체 인구 #{f(st['tot'])}명의 #{data['share']}입니다. "
      sm << "전국 평균 #{data['natShare']}보다 #{format('%.1f', diff.abs)}%p #{higher ? '높습니다' : '낮습니다'}. "
      sm << "전국 #{rk_n}개 시군구 중 #{lab} 비율 #{rk}위입니다. " if rk
      top = data['byCount'].first
      sm << "#{lab} 인구가 가장 많은 동네는 #{top['name']}(#{top['n']}명)입니다." if top
      data['summary'] = sm
      seo("#{d} #{s} #{nm} 인구 #{f(n)}명 (#{data['share']}) - 동네별 #{lab} 인구 (#{IText.ymshort(meta['ym'])})", "#{d} #{s} #{nm} 인구 #{f(n)}명, 전체의 #{data['share']}(전국 평균 #{data['natShare']}). #{lab} 인구가 많은 동네와 비율이 높은 동네 순위.")
      top_share = data['byShare'].first
      faq([["#{s} #{lab} 인구는 몇 명인가요?", "#{data['ym']} 말일 기준 #{d} #{s}의 #{nm} 주민등록 인구는 #{f(n)}명이고, 전체 인구의 #{data['share']}입니다."],
           ["#{s}에서 #{lab} 인구가 가장 많은 동네는 어디인가요?", top ? "#{IText.i_ga(top['name'])} #{top['n']}명으로 가장 많습니다. 비율로는 #{IText.i_ga(top_share ? top_share['name'] : top['name'])} 가장 높습니다." : '아래 표에서 동네별로 비교할 수 있습니다.'],
           ["#{s}의 #{lab} 비율은 전국 평균과 비교하면 어떤가요?", "#{s}의 #{lab} 비율은 #{data['share']}로 전국 평균 #{data['natShare']}보다 #{format('%.1f', diff.abs)}%p #{higher ? '높습니다' : '낮습니다'}."]])
    end
  end

  class SgPage < AreaBase
    def initialize(site, d, s, st, ds, meta)
      setup(site, "region/#{d}/#{s}", 'sigungu')
      data['doShort'] = d
      data['sigungu'] = s
      data['city'] = IText.city_of(s)
      data['cityUrl'] = data['city'] ? InguGenerator.sg_url(d, data['city'], true) : nil
      fill_common(st, ds, meta)
      data['dongRows'] = dong_rows(ds)
      ls = lists(ds)
      %w[old young single].each { |k| data[k] = ls[k].map { |x| mini(x, k) } }
      data['topDong'] = ds.max_by { |x| x['tot'] }['dong']
      data['ageLinks'] = age_links(d, s, st)
      data['sgLinks'] = { 'apt' => "https://wooaapt.wooahouse.com/region/#{InguGenerator.q(d)}/#{InguGenerator.q(s)}/", 'biz' => "https://wooasanggwon.wooahouse.com/sg/#{InguGenerator.q(d)}/#{InguGenerator.q(s)}/" }
      ym12l = IText.ymlabel(IText.month_add(meta['ym'], -12))
      sm = +"#{d} #{IText.eun_neun(s)} #{data['ym']} 기준 주민등록 인구 #{f(st['tot'])}명, #{st['dongs']}개 동네로 이뤄져 있습니다. "
      sm << "세대수는 #{f(st['hh'])}세대(세대당 #{data['hhn']}명)이고 1인 가구 비율은 #{data['r1']}입니다. " if st['hh'].positive?
      sm << "평균 연령은 #{data['avg']}세이고 65세 이상 고령 인구 비율은 #{data['r65']}, 14세 이하는 #{data['r014']}입니다. 인구가 가장 많은 동네는 #{data['topDong']}입니다. "
      sm << "#{ym12l} 대비 1년간 #{IText.sdiff(st['d12'])}(#{data['g12']}) #{st['d12'] >= 0 ? '늘었습니다' : '줄었습니다'}." if st['d12']
      data['summary'] = sm
      seo("#{d} #{s} 인구·세대수 (#{IText.ymshort(meta['ym'])}) - 동네별 인구·고령화·1인가구", "#{d} #{s} 인구 #{f(st['tot'])}명#{st['hh'].positive? ? ", 세대수 #{f(st['hh'])}세대" : ''}, 65세 이상 #{data['r65']}, 평균 연령 #{data['avg']}세. 동네별 인구와 증감, 1인 가구 비율, 연령대별 구성.")
      faq([["#{s} 인구는 몇 명인가요?", "#{data['ym']} 말일 기준 #{d} #{s}의 주민등록 인구는 #{f(st['tot'])}명입니다. 남자 #{f(st['male'])}명, 여자 #{f(st['fem'])}명이며 #{st['dongs']}개 동네로 나뉩니다."],
           ["#{s}에서 인구가 가장 많은 동네는 어디인가요?", "#{data['topDong']}#{IText.hangul_tail?(data['topDong']) ? (IText.batchim?(data['topDong']) ? '이' : '') : ''}입니다. 아래 표에서 동네별 인구·65세 이상 비율·1인 가구 비율·평균 연령·1년 증감을 비교할 수 있습니다."],
           ["#{s} 고령 인구 비율은 얼마인가요?", "65세 이상 인구가 #{f(st['old65'])}명으로 전체의 #{data['r65']}이고, 평균 연령은 #{data['avg']}세입니다. 동네마다 크게 다르니 표의 65세 이상 비율 열을 비교해 보세요."]])
    end
  end

  class CityPage < AreaBase
    def initialize(site, d, c, st, gus, ds, meta)
      setup(site, "region/#{d}/#{c}", 'city')
      data['doShort'] = d
      data['sigungu'] = c
      fill_common(st, ds, meta)
      data['guRows'] = area_rows(gus, d)
      data['dongRows'] = dong_rows(ds).first(80)
      data['dongTotal'] = ds.size
      data['ageLinks'] = age_links(d, c, st)
      ls = lists(ds)
      %w[old young single].each { |k| data[k] = ls[k].map { |x| mini(x, k) } }
      data['sgLinks'] = { 'apt' => "https://wooaapt.wooahouse.com/region/#{InguGenerator.q(d)}/#{InguGenerator.q(c)}/" }
      sm = +"#{d} #{IText.eun_neun(c)} #{data['ym']} 기준 주민등록 인구 #{f(st['tot'])}명으로 #{gus.size}개 구, #{st['dongs']}개 동네로 이뤄져 있습니다. 인구가 가장 많은 구는 #{gus.first['sg']}(#{f(gus.first['tot'])}명)입니다. "
      sm << "평균 연령은 #{data['avg']}세, 65세 이상 고령 인구 비율은 #{data['r65']}이고 1인 가구 비율은 #{data['r1']}입니다. " if st['r1']
      sm << "1년간 인구는 #{IText.sdiff(st['d12'])}(#{data['g12']}) #{st['d12'] >= 0 ? '늘었습니다' : '줄었습니다'}." if st['d12']
      data['summary'] = sm
      seo("#{d} #{c} 인구·세대수 (#{IText.ymshort(meta['ym'])}) - 구별·동네별 인구", "#{d} #{c} 인구 #{f(st['tot'])}명, #{gus.size}개 구. 구별 인구와 65세 이상 비율, 1인 가구 비율, 평균 연령, 1년 인구 증감.")
      faq([["#{c} 인구는 몇 명인가요?", "#{data['ym']} 말일 기준 #{d} #{c}의 주민등록 인구는 #{f(st['tot'])}명입니다. #{gus.map { |g| "#{g['sg']} #{f(g['tot'])}명" }.first(5).join(', ')} 등으로 구성됩니다."],
           ["#{c}에서 인구가 가장 많은 구는 어디인가요?", "#{IText.i_ga(gus.first['sg'])} #{f(gus.first['tot'])}명으로 가장 많습니다."]])
    end
  end

  class DoPage < AreaBase
    def initialize(site, d, st, rows, ds, meta)
      setup(site, "region/#{d}", 'do')
      data['doShort'] = d
      fill_common(st, ds, meta)
      data['sgRows'] = area_rows(rows, d)
      ls = lists(ds)
      %w[old young single].each { |k| data[k] = ls[k].map { |x| mini(x, k) } }
      data['sgCount'] = rows.size
      sm = +"#{d}의 주민등록 인구는 #{data['ym']} 기준 #{f(st['tot'])}명, #{rows.size}개 시군구·#{st['dongs']}개 읍면동입니다. "
      sm << "세대수는 #{f(st['hh'])}세대이고 1인 가구 비율은 #{data['r1']}입니다. " if st['hh'].positive?
      sm << "평균 연령은 #{data['avg']}세, 65세 이상 고령 인구 비율은 #{data['r65']}이며, 1년간 인구는 #{IText.sdiff(st['d12'])}(#{data['g12']}) #{st['d12'] >= 0 ? '늘었습니다' : '줄었습니다'}." if st['d12']
      data['summary'] = sm
      seo("#{d} 인구·세대수 (#{IText.ymshort(meta['ym'])}) - 시군구별 인구·고령화·1인가구", "#{d} 인구 #{f(st['tot'])}명, #{rows.size}개 시군구. 시군구별 인구와 65세 이상 비율, 1인 가구 비율, 평균 연령, 1년 증감.")
      faq([["#{d} 인구는 몇 명인가요?", "#{data['ym']} 말일 기준 #{d}의 주민등록 인구는 #{f(st['tot'])}명입니다."],
           ["#{d}에서 인구가 가장 많은 시군구는 어디인가요?", "#{IText.i_ga(rows.first['sg'])} #{f(rows.first['tot'])}명으로 가장 많습니다. 아래 표에서 시군구별로 비교할 수 있습니다."]])
    end
  end

  # ── 랭킹 ────────────────────────────────────────────
  class RankPage < IBasePage
    def initialize(site, kind, spec, d, rows, meta)
      if d
        setup(site, "rank/#{kind}/#{d}", 'rank')
        scope = d
      else
        setup(site, "rank/#{kind}", 'rank')
        scope = '전국'
      end
      data['kind'] = kind
      data['scope'] = scope
      data['doShort'] = d
      data['rankTitle'] = spec[:title]
      data['ym'] = IText.ymlabel(meta['ym'])
      data['cols'] = spec[:cols]
      data['count'] = rows.size
      data['desc'] = spec[:desc]
      data['rows'] = rows.each_with_index.map do |r, i|
        c = case kind
            when 'pop' then [f(r['tot']), r['hh'] ? f(r['hh']) : '-', r['hhn'] ? format('%.2f', r['hhn']) : '-']
            when 'single' then [IText.pct(r['r1']), f(r['h1']), f(r['hh'])]
            when 'old' then [IText.pct(r['r65']), f(r['old65']), f(r['tot'])]
            when 'young' then [IText.pct(r['r2039']), f(r['ag'][2] + r['ag'][3]), f(r['tot'])]
            when 'kids' then [IText.pct(r['r014']), f(r['kid14']), f(r['tot'])]
            when 'avglow', 'avghigh' then ["#{format('%.1f', r['avg'])}세", "#{r['med']}세", f(r['tot'])]
            else [IText.spct(r['g12']), IText.sdiff(r['d12']), f(r['tot'])]
            end
        { 'rank' => i + 1, 'name' => r['dong'], 'url' => InguGenerator.dong_url(r), 'loc' => "#{r['do']} #{r['sg']}", 'c' => c }
      end
      top = rows.first
      sm = +"#{scope}에서 #{data['ym']} 기준 주민등록 통계로 #{spec[:desc]}대로 동네 #{rows.size}곳을 정리했습니다. "
      sm << "1위는 #{top['do']} #{top['sg']} #{top['dong']}입니다. " if top
      sm << '각 동네 이름을 누르면 연령대별 인구와 최근 인구 추이를 볼 수 있습니다.'
      data['summary'] = sm
      seo("#{scope} #{spec[:title]} TOP #{rows.size} (#{IText.ymshort(meta['ym'])})", "#{scope} #{spec[:title]} 순위. #{spec[:desc]} #{rows.size}곳, 인구·비율·증감 포함. 행정안전부 주민등록 인구통계 기준.")
    end
  end

  class SgRankPage < IBasePage
    def initialize(site, kind, spec, rows, meta)
      setup(site, "rank/#{kind}", 'rank')
      data['kind'] = kind
      data['scope'] = '전국'
      data['rankTitle'] = spec[:title]
      data['ym'] = IText.ymlabel(meta['ym'])
      data['cols'] = spec[:cols]
      data['count'] = rows.size
      data['desc'] = spec[:desc]
      data['rows'] = rows.each_with_index.map do |s, i|
        c = case kind
            when 'sg-pop' then [f(s['tot']), s['hh'].positive? ? f(s['hh']) : '-', "#{s['dongs']}곳"]
            when 'sg-old' then [IText.pct(s['r65']), f(s['old65']), f(s['tot'])]
            when 'sg-single' then [IText.pct(s['r1']), f(s['h1']), f(s['hh'])]
            else [IText.spct(s['g12']), s['d12'] ? IText.sdiff(s['d12']) : '-', f(s['tot'])]
            end
        { 'rank' => i + 1, 'name' => s['sg'], 'url' => InguGenerator.sg_url(s['do'], s['sg'], s['city']), 'loc' => s['do'], 'c' => c }
      end
      data['summary'] = "#{data['ym']} 기준 주민등록 통계로 #{spec[:desc]}대로 #{rows.size}곳을 정리했습니다. 1위는 #{rows.first['do']} #{rows.first['sg']}입니다. 구가 있는 시는 시 단위로 함께 집계했습니다."
      seo("#{spec[:title]} TOP #{rows.size} (#{IText.ymshort(meta['ym'])})", "#{spec[:title]} 순위. #{spec[:desc]}, 인구·비율·증감 포함. 행정안전부 주민등록 인구통계 기준.")
    end
  end

  class RankIndexPage < IBasePage
    def initialize(site, kinds, sg_kinds, dos, meta)
      setup(site, 'rank', 'rankindex')
      data['kinds'] = kinds.map { |k, t| { 'k' => k, 't' => t } }
      data['sgKinds'] = sg_kinds.map { |k, t| { 'k' => k, 't' => t } }
      data['dos'] = dos
      data['ym'] = IText.ymlabel(meta['ym'])
      seo("인구 랭킹 (#{IText.ymshort(meta['ym'])}) - 인구·1인가구·고령·평균연령·증가 동네", "주민등록 인구 기준 랭킹. 인구가 많은 동네, 1인 가구·65세 이상·20·30대·14세 이하 비율이 높은 동네, 평균 연령, 최근 1년 인구가 늘고 줄어든 동네를 전국·시도별로 확인하세요.")
    end
  end

  # 사이트맵: 5만 건 한도 때문에 40,000건씩 분할 + 인덱스
  class InguSitemapGenerator < Generator
    safe true
    priority :lowest
    CHUNK = 40_000

    def generate(site)
      urls = site.pages.reject { |p| p.url.to_s.end_with?('.json', '.xml', '.txt', '.js', '.css') || p.url.to_s == '/404.html' || p.data['sitemap'] == false }.map { |p| p.url }.uniq
      base = site.config['url'].to_s
      chunks = urls.each_slice(CHUNK).to_a
      chunks.each_with_index do |c, idx|
        body = +"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
        c.each { |u| body << "  <url><loc>#{base}#{u}</loc></url>\n" }
        body << "</urlset>\n"
        site.pages << raw_page(site, "sitemap-#{idx + 1}.xml", body)
      end
      index = +"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<sitemapindex xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
      chunks.each_index { |idx| index << "  <sitemap><loc>#{base}/sitemap-#{idx + 1}.xml</loc></sitemap>\n" }
      index << "</sitemapindex>\n"
      site.pages << raw_page(site, 'sitemap.xml', index)
      Jekyll.logger.info 'InguSitemap:', "#{urls.size}개 URL → #{chunks.size}개 사이트맵"
    end

    private

    def raw_page(site, name, content)
      pg = PageWithoutAFile.new(site, site.source, '', name)
      pg.content = content
      pg.data['layout'] = nil
      pg.data['sitemap'] = false
      pg
    end
  end
end
