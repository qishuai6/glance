// 定投计算器
const annualInvest = 10000;
const years = 22;
let total = 0;
for (let i = 0; i < years; i++) {
  total = (total + annualInvest) * 1.125;
}
console.log(`22 岁账户: ${total.toFixed(0)} 元`);
