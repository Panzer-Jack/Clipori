(() => {
  'use strict';
  const english = {};
  const textNodes = document.querySelectorAll('[data-i18n]');
  const ariaNodes = document.querySelectorAll('[data-i18n-aria]');
  textNodes.forEach(node => {
    const copy = node.cloneNode(true);
    copy.querySelectorAll('br').forEach(br => br.replaceWith('\n'));
    english[node.dataset.i18n] = copy.textContent;
  });
  ariaNodes.forEach(node => { english[node.dataset.i18nAria] = node.getAttribute('aria-label'); });
  Object.assign(english, {
    title: 'Clipori — Keep every little spark.',
    description: 'A lightweight, open-source AI clipboard and notes app for Mac. Keep what you copy, find it with AI, and get back to creating.',
    resumeMotion: 'Play animation',
    pause: 'Pause demo', copied: 'Copied', copySuccess: 'Copied. Paste into Terminal to run.',
    copyFallback: 'Select the command and press ⌘C to copy.',
  });
const chinese = {
  tourClassify: '分类，交给 AI', tourEdit: '备忘，接着写',
  classifyTitle: '新的记忆，\n自动找到自己的位置。', classifyDescription: '开启 AI 自动分类后，新复制的内容会由 AI 判断并归入合适的分类。分类由你预设、自由修改，整理时让 AI 搭把手。', classifyHint: '按需开启 · 使用你配置的 AI 服务',
  demoAutoClassify: 'AI 自动分类', demoCodeTitle: '再柔和一点的回弹', demoClassifying: '正在寻找合适的分类…', demoCodeCategory: '代码', demoClassified: '分类这件小事，AI 帮你做好了。',
  editTitle: '不止复制，\n也是可以继续写的备忘。', editDescription: '打开过去的记录，修改内容，或者追加刚想到的几句话。保存后，下次取用的就是更新后的记忆。', editHint: '改一改旧内容，再添一点新想法。',
  demoEditMemory: '编辑备忘', demoTitleLabel: '标题', demoContentLabel: '内容', demoExtraNote: '记得带上相机，给闲逛留一点时间。', demoSave: '保存', demoUpdated: '已更新', demoEditSaved: '这条记忆，又多了一点新想法。',
    tourLabel: '探索 Clipori 功能', tourTabs: '功能演示', tourCapture: '复制，即记住', tourPaste: '顺手，贴回去', tourOrganize: '拖动，归个类', tourRecall: '忘了，问问 AI',
    captureTitle: '复制这一刻，\n留给需要的那一刻。', captureDescription: '文字、链接、截图，复制的同时就被悄悄记下。不用刻意保存，也能在需要时回来找。', captureHint: '熟悉的复制，多一份记忆。',
    pasteTitle: '灵感不打断，\n双击就回到当下。', pasteDescription: '唤出卡片栏，找到刚才那条内容，双击贴回正在使用的应用。顺手取用，然后继续。', pasteHint: '唤起、选中、贴回去。',
    organizeTitle: '几个小念头，\n拖进同一个小天地。', organizeDescription: '多选几张卡片，一起拖入分类。工作、生活、下一次灵感，各有各的位置。', organizeHint: '多选几张，一起归类。',
    recallTitle: '记得大概，\n就可以问问它。', recallDescription: '不用想起准确的关键词，用自然语言描述就好。连接你自己的 AI 服务，从历史里找回相关内容。', recallHint: '你的记忆，你的 AI。',
    demoNotes: '备忘录', demoWeekend: '一点周末计划', demoBookshop: '下雨天的书店', demoAddress: '银杏路 42 号 · 门口有一只橘猫。', demoTime: '周六，10:00–20:00', demoMemories: '全部记忆', demoLife: '生活', demoSpark: '一闪而过的灵感', demoInspiration: '灵感', demoLearning: '学习', demoSaved: '这个小念头，已经记住了。', demoSaturday: '周六，就去这里吧。', demoPasted: '贴好了，继续刚才的事。', demoIdea: '做一点小东西，做自己喜欢的。', demoDesign: '让界面再柔和一点', demoOrganized: '两个小念头，找到新位置。', demoQuestion: '之前那家有猫的书店在哪？', demoFound: '从你的历史中找到了', demoAnswer: '银杏路 42 号，周六 10:00–20:00 营业。没错，门口有一只橘猫。',
    tourCaption: '功能示意动画 · 示例数据 · 左右切换探索', pauseMotion: '暂停动效', resumeMotion: '播放动效', previousFeature: '上一个功能', nextFeature: '下一个功能',
    title: 'Clipori — 留住每一闪灵感。',
    description: '轻巧、灵动的 Mac AI 剪贴板与备忘录。自动留住复制的文字、链接和截图，用 AI 找回记忆。免费开源，即刻下载。',
    skip: '跳到正文', brandLabel: '你的小小记忆库', navigation: '主导航',
    navFeatures: '认识 Clipori', navInstall: '安装使用', eyebrow: '为 MAC 而生 · 免费开源',
    heroLineOne: '复制过的灵感，', heroLineTwo: '随时回到手边。',
    heroDescription: '一段文字、一张截图、一个忽然冒出的念头。\n让轻巧的 AI 剪贴板帮你记住，留点心思给创造。',
    download: '下载 Mac 版', watchDemo: '看看它如何工作',
    compatibility: 'macOS 14+ · 支持 Apple Silicon 与 Intel · 免费开源',
    heroNote: '少一点记挂，\n多一点灵感。', demoTitle: '让剪贴板，也有一点灵动。', oneShortcut: '一个快捷键，就在手边',
    demoWindow: '和 Clipori 相处的片刻', videoLabel: 'Clipori 产品功能示意动画',
    demoCaption: '产品示意动画 · 示例内容与预设 AI 回复', play: '播放演示', pause: '暂停演示',
    demoHint: '复制、找回，然后继续创造。', gifFallback: '查看 GIF 演示',
    featuresEyebrow: '小小的软件，轻一点的日常', featuresTitle: '少找一会儿，多做一点。',
    featureOneTitle: '复制即记住，随用随取。',
    featureOneDescription: '文字、链接、代码、截图，自动收进底部卡片栏。单击复制，双击粘贴，每个念头都能接着用。',
    featureOneDetail: '你的历史记录，一键唤起', featureTwoTitle: '记不清了？问问 AI。',
    featureTwoDescription: '忘了确切的关键词，也能用一句话找回。接入你自己的 OpenAI 或 Claude 兼容服务，让记忆有迹可循。',
    featureTwoDetail: '你的 AI，由你来配置', featureThreeTitle: '为灵感，留一个位置。',
    featureThreeDescription: '多选卡片，拖进分类；固定常用内容，补上几句备忘，或放一张便笺在桌面。把记忆整理成喜欢的样子。',
    featureThreeDetail: '一点秩序，按你的方式', privacyTitle: '本地保存，自己掌握。',
    privacyDescription: '历史留在 Mac，密钥存于钥匙串。使用 AI 时，问题与相关文字会发送至你选择的服务。',
    installEyebrow: '给剪贴板，安一个新家', installTitle: '下一个顺手的习惯，\n从这里开始。',
    installDescription: '简单几步，就能开始。\n无需 Xcode，也不必注册账号。', viewReleases: '前往最新 Release',
    stepOneTitle: '下载，放进「应用程序」', releaseLink: '前往 GitHub Releases',
    stepOneDescription: '，M 系列芯片选择 arm64，Intel 选择 x86_64。打开 DMG 或解压 ZIP，将 Clipori.app 拖入「应用程序」。',
    stepTwoTitle: '首次启动前，执行一条命令',
    stepTwoDescription: '当前版本尚未通过 Apple 公证。确认从本项目 Releases 下载后，在「终端」执行以下命令，移除该应用的隔离标记：',
    copyCommand: '复制安装命令', copy: '复制', copied: '已复制', copySuccess: '已复制，可粘贴到终端执行。', copyFallback: '请选中命令，按 ⌘C 复制。',
    stepThreeTitle: '打开 Clipori，随手复制一点什么', stepThreeDescription: '应用常驻菜单栏，按 ',
    stepThreeEnd: ' 唤起卡片栏。复制文字或图片后，就会自动收录。',
    pasteSetup: '开启双击直接粘贴', pasteSetupDescription: '前往「系统设置 → 隐私与安全性 → 辅助功能」，开启 Clipori 权限。未授权时，仍可单击卡片复制，再切回目标应用按 ⌘V 粘贴。',
    aiSetup: '接入你自己的 AI', aiSetupDescription: '在「Clipori 设置 → AI」选择 OpenAI 或 Claude 格式，填写接口地址、模型和 API Key，测试并保存。未配置 AI 也能使用历史记录和关键词搜索；自动分类可按需开启。',
    faqEyebrow: '还有几件小事', faqTitle: '你可能也想知道。', faqFreeTitle: 'Clipori 免费吗？',
    faqFreeDescription: '目前软件开源且免费，以 Apache 2.0 协议开源。',
    faqHistoryTitle: '历史记录能保留多久？', faqHistoryDescription: '新安装默认保留 30 天。可自行选择 1 天、1 周、1 个月、1 年或永久。固定记录和固定分类（Pinboard）中的内容不会自动清理。',
    faqPhoneTitle: '可以与 iPhone 互通吗？', faqPhoneDescription: '当前发布的是 Mac 版。iPhone 客户端与 iCloud 同步正在开发，跨设备同步还未开放日常使用。',
    faqScreenshotTitle: '截图也可以收录吗？', faqScreenshotDescription: '可以。按 ⌃⇧⌘4 将选区截图复制到剪贴板，Clipori 会自动收录，选中后按空格预览。只保存为文件的截图不会自动收录。',
    closingTitle: '下一闪灵感，放心交给它。', closingDescription: '把小事记下，把心思留给喜欢的事。',
    footerNote: '· 带着一点好奇，慢慢打磨。', feedback: '问题反馈',
  };
  const video = document.getElementById('demo-video');
  const videoToggle = document.getElementById('video-toggle');
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  const languageButton = document.getElementById('language-switch');
  let language;
  let copyTimer;
  let manuallyPaused = false;
  let videoInView = false;
  const t = key => (language === 'zh' ? chinese[key] : english[key]) || english[key];
  function updatePlaybackLabel() { videoToggle.textContent = t(video.paused ? 'play' : 'pause'); }
  function setLanguage(next, persist = false) {
    language = next;
    document.documentElement.lang = next === 'zh' ? 'zh-CN' : 'en';
    textNodes.forEach(node => { node.textContent = t(node.dataset.i18n); });
    ariaNodes.forEach(node => { node.setAttribute('aria-label', t(node.dataset.i18nAria)); });
    document.title = t('title');
    document.querySelector('meta[name="description"]').content = t('description');
    document.querySelector('meta[property="og:title"]').content = t('title');
    document.querySelector('meta[property="og:description"]').content = t('description');
    document.querySelector('meta[property="og:image"]').content = `https://panzer-jack.github.io/Clipori/assets/clipori-demo-poster-${next}.jpg`;
    languageButton.setAttribute('aria-label', next === 'zh' ? 'Switch to English' : '切换到中文');
    document.getElementById('language-label').textContent = next === 'zh' ? 'EN' : '中文';
    document.getElementById('gif-link').href = `assets/clipori-demo${next === 'zh' ? '-zh' : ''}.gif`;
    video.autoplay = false;
    video.poster = `assets/clipori-demo-poster-${next}.jpg`;
    video.width = 1200; video.height = next === 'zh' ? 676 : 720;
    video.src = `assets/clipori-demo-${next}.mp4`;
    video.load();
    syncVideoPlayback();
    document.getElementById('copy-feedback').textContent = '';
    clearTimeout(copyTimer);
    updatePlaybackLabel();
    document.dispatchEvent(new CustomEvent("clipori-language", { detail: { language, play: t("resumeMotion"), pause: t("pauseMotion") } }));
    if (persist) {
      try { localStorage.setItem('clipori-language', next); } catch (_) { /* Private browsing remains usable. */ }
      const url = new URL(location.href); url.searchParams.set('lang', next);
      history.replaceState(null, '', url);
    }
  }
  let preference;
  try { preference = localStorage.getItem('clipori-language'); } catch (_) { /* Use browser language. */ }
  const requested = new URLSearchParams(location.search).get('lang');
  const initial = ['zh', 'en'].includes(requested) ? requested : ['zh', 'en'].includes(preference) ? preference : navigator.language.toLowerCase().startsWith('zh') ? 'zh' : 'en';
  setLanguage(initial);
  languageButton.addEventListener('click', () => setLanguage(language === 'zh' ? 'en' : 'zh', true));
function syncVideoPlayback() {
  if (videoInView && !document.hidden && !reducedMotion.matches && !manuallyPaused) video.play().catch(updatePlaybackLabel);
  else video.pause();
}
videoToggle.addEventListener('click', () => {
  manuallyPaused = !video.paused;
  if (manuallyPaused) video.pause(); else video.play().catch(updatePlaybackLabel);
});
video.addEventListener('play', updatePlaybackLabel);
video.addEventListener('pause', updatePlaybackLabel);
document.getElementById('watch-demo').addEventListener('click', () => {
  manuallyPaused = false; video.play().catch(updatePlaybackLabel);
});
if ('IntersectionObserver' in window) {
  const observer = new IntersectionObserver(entries => {
    videoInView = entries[0].isIntersecting; syncVideoPlayback();
  }, { threshold: 0.15 });
  observer.observe(video);
} else { videoInView = true; syncVideoPlayback(); }
document.addEventListener('visibilitychange', syncVideoPlayback);
if (reducedMotion.addEventListener) reducedMotion.addEventListener('change', syncVideoPlayback);
  document.getElementById('copy-command').addEventListener('click', async () => {
    const command = document.getElementById('install-command');
    try {
      await navigator.clipboard.writeText(command.textContent);
      document.getElementById('copy-label').textContent = t('copied');
      document.getElementById('copy-feedback').textContent = t('copySuccess');
    } catch (_) {
      const range = document.createRange(); range.selectNodeContents(command);
      const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
      document.getElementById('copy-feedback').textContent = t('copyFallback');
    }
    clearTimeout(copyTimer);
    copyTimer = setTimeout(() => { document.getElementById('copy-label').textContent = t('copy'); }, 2500);
  });
  document.getElementById('year').textContent = new Date().getFullYear();
})();
