const Stripe = require('stripe');

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  if (req.method !== 'GET') return res.status(405).json({ error: 'Method not allowed' });

  const STRIPE_SK = process.env.STRIPE_SECRET_KEY;
  if (!STRIPE_SK) return res.status(500).json({ error: 'Clé Stripe manquante' });

  const stripe = new Stripe(STRIPE_SK);
  const { session_id } = req.query;

  if (!session_id) return res.status(400).json({ error: 'session_id manquant' });

  try {
    const session = await stripe.checkout.sessions.retrieve(session_id);

    return res.status(200).json({
      payment_status: session.payment_status,
      amount: session.amount_total,
      metadata: session.metadata,
    });
  } catch (err) {
    console.error('Stripe verify error:', err);
    return res.status(500).json({ error: err.message });
  }
};
