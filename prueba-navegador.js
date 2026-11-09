const { chromium } = require('playwright');
const tiendas = {
  Walmart: 'https://www.walmart.com.mx/browse/videojuegos/play-station-5/consolas-ps5/264999_970024_970025',
  Bodega: 'https://www.bodegaaurrera.com.mx/browse/videojuegos/playstation-5/consolas-ps5/264999_970024_970025',
  Soriana: 'https://www.soriana.com/buscar?q=consola%20playstation%205',
};
(async () => {
  const b = await chromium.launch();
  const ctx = await b.newContext({ locale: 'es-MX', timezoneId: 'America/Mexico_City' });
  for (const [t, u] of Object.entries(tiendas)) {
    const p = await ctx.newPage();
    try {
      await p.goto(u, { waitUntil: 'domcontentloaded', timeout: 45000 });
      await p.waitForTimeout(8000);
      const txt = await p.evaluate(() => document.body.innerText);
      const muro = /mant[eé]n presionado|no eres un robot|captcha|verifica que eres|access denied/i.test(txt);
      const precios = (txt.match(/\$\s?\d{1,2},\d{3}/g) || []).length;
      const ps = (txt.match(/playstation 5|ps5/gi) || []).length;
      console.log(`RES ${t}: muro=${muro} chars=${txt.length} precios=${precios} menciones_ps5=${ps} titulo=${(await p.title()).slice(0,60)}`);
      if (!muro) console.log('MUESTRA ' + t + ': ' + txt.replace(/\s+/g,' ').slice(0,300));
    } catch (e) { console.log(`RES ${t}: ERROR ${e.message.slice(0,100)}`); }
    await p.close();
  }
  await b.close();
})();