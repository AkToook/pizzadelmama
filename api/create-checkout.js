export default async function handler(req, res) {
  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const { amount, description, reference, customer_name, customer_phone, delivery_address } = req.body;

  if (!amount || amount < 1) {
    return res.status(400).json({ error: 'Montant invalide' });
  }

  const SUMUP_API_KEY = process.env.SUMUP_API_KEY;
  const SUMUP_MERCHANT_CODE = process.env.SUMUP_MERCHANT_CODE;

  if (!SUMUP_API_KEY || !SUMUP_MERCHANT_CODE) {
    return res.status(500).json({ error: 'Configuration SumUp manquante' });
  }

  // Generate unique reference
  const checkoutRef = reference || `NPR-${Date.now()}-${Math.random().toString(36).substr(2, 6)}`;

  try {
    const response = await fetch('https://api.sumup.com/v0.1/checkouts', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${SUMUP_API_KEY}`
      },
      body: JSON.stringify({
        amount: parseFloat(amount),
        currency: 'EUR',
        checkout_reference: checkoutRef,
        merchant_code: SUMUP_MERCHANT_CODE,
        description: description || 'Commande New Pizza Reims',
        redirect_url: 'https://pizzareims.vercel.app/confirmation.html?ref=' + encodeURIComponent(checkoutRef),
        hosted_checkout: { enabled: true }
      })
    });

    const data = await response.json();

    if (!response.ok) {
      console.error('SumUp error:', data);
      return res.status(response.status).json({ error: data.message || 'Erreur SumUp', details: data });
    }

    return res.status(200).json({
      checkout_id: data.id,
      checkout_url: data.hosted_checkout_url,
      reference: checkoutRef,
      amount: data.amount,
      status: data.status
    });

  } catch (err) {
    console.error('Server error:', err);
    return res.status(500).json({ error: 'Erreur serveur' });
  }
}
