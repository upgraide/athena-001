import { VertexAI, HarmCategory, HarmBlockThreshold } from '@google-cloud/vertexai';
import winston from 'winston';
import { Transaction } from '../models/transaction.model';

export interface CategorizationResult {
  category: string;
  subcategory?: string;
  confidence: number;
  isBusinessExpense: boolean;
  isRecurring: boolean;
  reasoning: string;
}

export class MLCategorizationService {
  private vertexAI: VertexAI;
  private model: any;

  constructor(
    private logger: winston.Logger,
    projectId?: string,
    location: string = 'us-central1'
  ) {
    // Initialize Vertex AI
    this.vertexAI = new VertexAI({
      project: projectId || process.env.GCP_PROJECT_ID!,
      location
    });

    // Initialize Gemini Pro model
    this.model = this.vertexAI.getGenerativeModel({
      model: 'gemini-1.5-pro-001',
      generationConfig: {
        maxOutputTokens: 1024,
        temperature: 0.2,
        topP: 0.8,
        topK: 40,
      },
      safetySettings: [
        {
          category: HarmCategory.HARM_CATEGORY_HATE_SPEECH,
          threshold: HarmBlockThreshold.BLOCK_ONLY_HIGH,
        },
        {
          category: HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
          threshold: HarmBlockThreshold.BLOCK_ONLY_HIGH,
        },
        {
          category: HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
          threshold: HarmBlockThreshold.BLOCK_ONLY_HIGH,
        },
        {
          category: HarmCategory.HARM_CATEGORY_HARASSMENT,
          threshold: HarmBlockThreshold.BLOCK_ONLY_HIGH,
        }
      ]
    });
  }

  async categorizeTransaction(
    transaction: Partial<Transaction>,
    userHistory: Transaction[]
  ): Promise<CategorizationResult> {
    try {
      // Find similar past transactions
      const similar = this.findSimilarTransactions(transaction, userHistory);
      
      // Build context from user's categorization patterns
      const context = this.buildCategorizationContext(similar);
      
      // Build the prompt
      const prompt = `You are a financial transaction categorization expert. Analyze this transaction and categorize it based on the user's historical patterns.

Transaction to categorize:
- Amount: ${transaction.currency} ${transaction.amount}
- Merchant: ${transaction.merchantName || 'Unknown'}
- Description: ${transaction.description}
- Date: ${transaction.date}
- Bank Category: ${transaction.metadata?.bankCategory || 'None'}

User's similar past transactions:
${context}

Available categories: food, transportation, shopping, utilities, entertainment, health, business, travel, personal, income, transfer

Important considerations:
1. Is this likely a business expense based on merchant, amount, and context?
2. What category best fits based on the user's past categorization behavior?
3. Does this look like a recurring subscription or regular payment?
4. Consider common merchant patterns (e.g., Uber/Lyft = transportation, Starbucks = food)

Respond with a JSON object only:
{
  "category": "main_category",
  "subcategory": "specific_type_or_null",
  "confidence": 0.0-1.0,
  "isBusinessExpense": boolean,
  "isRecurring": boolean,
  "reasoning": "brief explanation"
}`;

      const result = await this.model.generateContent(prompt);
      const response = result.response.text();
      
      // Parse JSON response
      const jsonMatch = response.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        throw new Error('Failed to parse model response');
      }
      
      const categorization = JSON.parse(jsonMatch[0]);
      
      this.logger.info('ML categorization completed', {
        transactionId: transaction.id,
        category: categorization.category,
        confidence: categorization.confidence
      });
      
      return categorization;
    } catch (error) {
      this.logger.error('ML categorization failed', { error });
      
      // Fallback to rule-based categorization
      return this.fallbackCategorization(transaction);
    }
  }

  private findSimilarTransactions(
    transaction: Partial<Transaction>,
    history: Transaction[]
  ): Transaction[] {
    return history
      .filter(t => {
        // Similar merchant
        if (t.merchantName && transaction.merchantName) {
          const similarity = this.calculateSimilarity(
            t.merchantName.toLowerCase(),
            transaction.merchantName.toLowerCase()
          );
          if (similarity > 0.8) return true;
        }
        
        // Similar amount (within 10%)
        if (transaction.amount && Math.abs(t.amount - transaction.amount) / transaction.amount < 0.1) {
          return true;
        }
        
        // Similar description keywords
        if (t.description && transaction.description) {
          const tKeywords = this.extractKeywords(t.description);
          const transKeywords = this.extractKeywords(transaction.description);
          const commonKeywords = tKeywords.filter(k => transKeywords.includes(k));
          if (commonKeywords.length >= 2) return true;
        }
        
        return false;
      })
      .slice(0, 10);
  }

  private calculateSimilarity(str1: string, str2: string): number {
    // Simple Jaccard similarity for merchant names
    const set1 = new Set(str1.split(/\s+/));
    const set2 = new Set(str2.split(/\s+/));
    
    const intersection = new Set([...set1].filter(x => set2.has(x)));
    const union = new Set([...set1, ...set2]);
    
    return intersection.size / union.size;
  }

  private extractKeywords(text: string): string[] {
    // Extract meaningful keywords from transaction description
    const stopWords = new Set(['the', 'and', 'or', 'at', 'in', 'on', 'for', 'to', 'of']);
    return text.toLowerCase()
      .split(/\s+/)
      .filter(word => word.length > 3 && !stopWords.has(word));
  }

  private buildCategorizationContext(similar: Transaction[]): string {
    if (similar.length === 0) {
      return 'No similar transactions found.';
    }
    
    return similar.map(t => 
      `- ${t.merchantName}: ${t.currency} ${t.amount} -> ${t.category}${t.subcategory ? `/${t.subcategory}` : ''} (Business: ${t.isBusinessExpense})`
    ).join('\n');
  }

  private fallbackCategorization(transaction: Partial<Transaction>): CategorizationResult {
    // Enhanced rule-based categorization as fallback
    const merchantName = (transaction.merchantName || '').toLowerCase();
    const description = (transaction.description || '').toLowerCase();
    const combined = `${merchantName} ${description}`;
    
    let category = 'other';
    let subcategory: string | undefined = undefined;
    let isBusinessExpense = false;
    let confidence = 0.6;
    
    // Food & Dining
    if (combined.match(/restaurant|cafe|coffee|food|eat|dine|lunch|dinner|breakfast|starbucks|mcdonald|subway|pizza/)) {
      category = 'food';
      subcategory = combined.includes('coffee') || combined.includes('starbucks') ? 'coffee' : 'restaurants';
      confidence = 0.8;
    }
    // Transportation
    else if (combined.match(/uber|lyft|taxi|transport|fuel|petrol|gas station|parking|transit|train|bus/)) {
      category = 'transportation';
      subcategory = combined.includes('fuel') || combined.includes('gas') ? 'fuel' : 
                   combined.includes('uber') || combined.includes('lyft') ? 'rideshare' : 'public';
      confidence = 0.85;
    }
    // Shopping
    else if (combined.match(/amazon|store|shop|mart|retail|walmart|target|ebay/)) {
      category = 'shopping';
      subcategory = combined.includes('amazon') || combined.includes('ebay') ? 'online' : 'retail';
      confidence = 0.75;
    }
    // Utilities
    else if (combined.match(/electric|water|gas|internet|phone|mobile|verizon|at&t|comcast|utility/)) {
      category = 'utilities';
      isBusinessExpense = true;
      confidence = 0.9;
    }
    // Entertainment
    else if (combined.match(/netflix|spotify|hulu|disney|cinema|movie|music|game|steam|xbox|playstation/)) {
      category = 'entertainment';
      subcategory = 'subscriptions';
      confidence = 0.85;
    }
    // Health & Fitness
    else if (combined.match(/gym|fitness|health|doctor|pharmacy|medical|hospital|cvs|walgreens/)) {
      category = 'health';
      subcategory = combined.includes('gym') || combined.includes('fitness') ? 'fitness' : 'medical';
      confidence = 0.8;
    }
    // Travel
    else if (combined.match(/hotel|airline|flight|airbnb|booking|expedia|travel/)) {
      category = 'travel';
      subcategory = combined.includes('hotel') || combined.includes('airbnb') ? 'accommodation' : 'transport';
      confidence = 0.85;
    }
    // Business expenses (additional patterns)
    else if (combined.match(/office|supplies|software|subscription|adobe|microsoft|slack|zoom/)) {
      category = 'business';
      isBusinessExpense = true;
      confidence = 0.8;
    }
    
    // Check for recurring patterns
    const isRecurring = combined.match(/subscription|monthly|recurring|membership/) !== null;
    
    return {
      category,
      subcategory,
      confidence,
      isBusinessExpense,
      isRecurring,
      reasoning: 'Categorized using enhanced pattern matching rules'
    };
  }

  async processFeedback(
    transactionId: string,
    userId: string,
    correction: {
      category: string;
      subcategory?: string;
      isBusinessExpense?: boolean;
    }
  ): Promise<void> {
    // This will be used to improve future categorizations
    this.logger.info('Processing categorization feedback', {
      transactionId,
      userId,
      correction
    });
    
    // In a production system, this would:
    // 1. Store the feedback for model retraining
    // 2. Update similar uncategorized transactions
    // 3. Adjust user-specific patterns
  }
}