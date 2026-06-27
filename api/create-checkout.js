const Stripe = require('stripe');

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const STRIPE_SK = process.env.STRIPE_SECRET_KEY;
  if (!STRIPE_SK) return res.status(500).json({ error: 'Clé Stripe manquante' });

  const stripe = new Stripe(STRIPE_SK);

  const { items, total, orderNum, customerName, customerPhone, deliveryMode, address, special } = req.body;

  if (!total || total < 1) {
    return res.status(400).json({ error: 'Montant invalide' });
  }

  try {
    const session = await stripe.checkout.sessions.create({
      payment_method_types: ['card'],
      mode: 'payment',
      line_items: [{
        price_data: {
          currency: 'eur',
          product_data: {
            name: 'Commande ' + (orderNum || '---') + ' — New Pizza Reims',
          },
          unit_amount: Math.round(total * 100),
        },
        quantity: 1,
      }],
      metadata: {
        orderNum: orderNum || '',
        customerName: customerName || '',
        customerPhone: customerPhone || '',
        deliveryMode: deliveryMode || '',
        address: address || '',
        special: special || '',
        items: JSON.stringify(items || []),
      },
      success_url: 'https://pizzareims.vercel.app/confirmation.html?session_id={CHECKOUT_SESSION_ID}',
      cancel_url: 'https://pizzareims.vercel.app/index.html#panier',
    });

    return res.status(200).json({
      url: session.url,
      sessionId: session.id,
    });

  } catch (err) {
    console.error('Stripe error:', err);
    return res.status(500).json({ error: err.message });
  }
};
