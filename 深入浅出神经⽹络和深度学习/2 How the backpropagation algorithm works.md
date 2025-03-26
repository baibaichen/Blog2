# 2 [How the backpropagation algorithm works](http://neuralnetworksanddeeplearning.com/chap2.html)

In the [last chapter](http://neuralnetworksanddeeplearning.com/chap1.html) we saw how neural networks can learn their weights and biases using the gradient descent algorithm. There was, however, a gap in our explanation: we didn't discuss how to compute the gradient of the cost function. That's quite a gap! In this chapter I'll explain a fast algorithm for computing such gradients, an algorithm known as *backpropagation*.

The backpropagation algorithm was originally introduced in the 1970s, but its importance wasn't fully appreciated until a [famous 1986 paper](http://www.nature.com/nature/journal/v323/n6088/pdf/323533a0.pdf) by [David Rumelhart](http://en.wikipedia.org/wiki/David_Rumelhart), [Geoffrey Hinton](http://www.cs.toronto.edu/~hinton/), and [Ronald Williams](http://en.wikipedia.org/wiki/Ronald_J._Williams). That paper describes several neural networks where backpropagation works far faster than earlier approaches to learning, making it possible to use neural nets to solve problems which had previously been insoluble. Today, the backpropagation algorithm is the workhorse of learning in neural networks.

第 1 章介绍了神经网络如何使用梯度下降算法来学习权重和偏置，但其中存在一个问题：没有讨论如何计算代价函数的梯度。本章会讲解计算这些梯度的快速算法——反向传播算法。

反向传播算法诞生于 20 世纪 70 年代，但直到 David Rumelhart、Geoffrey Hinton 和 Ronald Williams 于 1986 年发表了一篇著名的论文^1^，人们才意识到其重要性。这篇论文阐述了对于一些神经网络，反向传播算法比传统方法更快，这使得之前无法解决的问题可以诉诸神经网络。如今，反向传播算法已经成为神经网络学习的重要组成部分。

> 1. http://www.nature.com/nature/journal/v323/n6088/pdf/323533a0.pdf

This chapter is more mathematically involved than the rest of the book. If you're not crazy about mathematics you may be tempted to skip the chapter, and to treat backpropagation as a black box whose details you're willing to ignore. Why take the time to study those details?

The reason, of course, is understanding. At the heart of backpropagation is an expression for the partial derivative $\partial C / \partial w$ of the cost function $C$ with respect to any weight $w$ (or bias $b$) in the network. The expression tells us how quickly the cost changes when we change the weights and biases. And while the expression is somewhat complex, it also has a beauty to it, with each element having a natural, intuitive interpretation. And so backpropagation isn't just a fast algorithm for learning. It actually gives us detailed insights into how changing the weights and biases changes the overall behaviour of the network. That's well worth studying in detail.

With that said, if you want to skim the chapter, or jump straight to the next chapter, that's fine. I've written the rest of the book to be accessible even if you treat backpropagation as a black box. There are, of course, points later in the book where I refer back to results from this chapter. But at those points you should still be able to understand the main conclusions, even if you don't follow all the reasoning.

本章比其他章包含更多数学内容。如果你对数学不是特别感兴趣，可以跳过本章，将反向传播当成一个黑盒，忽略其中的细节。既然如此，为何要研究这些细节呢？

答案是为了加强理解。反向传播的核心是对代价函数 $C$ 关于任何权重 $w$（或者偏置 $b$）的偏导数 $\partial C / \partial w$ 的表达式。该表达式用于计算改变权重和偏置时代价变化的快慢。尽管表达式有点复杂，但有其内在逻辑——每个元素都很直观。因此，反向传播不仅仅是一种快速的学习算法，实际上它还告诉我们如何通过改变权重和偏置来改变整个神经网络的行为，这也是学习反向传播细节的价值所在。

如前所述，你既可以阅读本章，也可以直接跳到下一章。即使把反向传播看作黑盒，也可以掌握书中的其余内容。当然，后文会涉及本章的结论。不过，对于这些知识点，即使你不了解推导细节，也应该能理解主要结论。

### 2.1 [Warm up: a fast matrix-based approach to computing the output from a neural network](http://neuralnetworksanddeeplearning.com/chap2.html#warm_up_a_fast_matrix-based_approach_to_computing_the_output_from_a_neural_network)

Before discussing backpropagation, let's warm up with a fast matrix-based algorithm to compute the output from a neural network. We actually already briefly saw this algorithm [near the end of the last chapter](http://neuralnetworksanddeeplearning.com/chap1.html#implementing_our_network_to_classify_digits), but I described it quickly, so it's worth revisiting in detail. In particular, this is a good way of getting comfortable with the notation used in backpropagation, in a familiar context.

讨论反向传播前，首先介绍一下如何通过基于矩阵的算法来计算神经网络的输出。实际上，1.6 节提到了这个算法，但未讨论细节，下面详述。这样做有助于你在熟悉的场景中理解反向传播中使用的矩阵表示。

Let's begin with a notation which lets us refer to weights in the network in an unambiguous way. We'll use $w^l_{jk}$ to denote the weight for the connection from the $k^{\rm th}$ neuron in the $(l-1)^{\rm th}$ layer to the $j^{\rm th}$ neuron in the $l^{\rm th}$ layer. So, for example, the diagram below shows the weight on a connection from the fourth neuron in the second layer to the second neuron in the third layer of a network:

首先给出神经网络中权重的清晰定义。$w^l_{jk}$ 表示第 $(l-1)^{\rm th}$ 层的第 $k^{\rm th}$ 个神经元到第 $l^{\rm th}$ 层第 $j^{\rm th}$ 个神经元的连接的权重。图 2-1 给出了神经网络中第 2 层的第 4 个神经元到第 3 层的第 2 个神经元的连接的权重。

![img](http://neuralnetworksanddeeplearning.com/images/tikz16.png)

This notation is cumbersome at first, and it does take some work to master. But with a little effort you'll find the notation becomes easy and natural. One quirk of the notation is the ordering of the $j$ and $k$ indices. You might think that it makes more sense to use $j$ to refer to the input neuron, and $k$ to the output neuron, not vice versa, as is actually done. I'll explain the reason for this quirk below.

这样的表示粗看上去比较奇怪，需要花一点时间消化。稍后你会发现这种表示方便且自然。下标 $j$ 和 $k$ 的顺序可能会引起困惑，有人觉得反过来更合理。下面介绍这样做的原因。

We use a similar notation for the network's biases and activations. Explicitly, we use $b^l_j$ for the bias of the $j^{\rm th}$ neuron in the $l^{\rm th}$ layer. And we use $a^l_j$ for the activation of the $j^{\rm th}$ neuron in the $l^{\rm th}$ layer. The following diagram shows examples of these notations in use:

神经网络的偏置和激活值也使用类似的表示，用 $b^l_j$ 表示第 $l^{\rm th}$ 层第 $j^{\rm th}$ 个神经元的偏置，用 $a^l_j$ 表示第 $l^{\rm th}$ 层第 $j^{\rm th}$ 个神经元的激活值。图 2-2 清楚地展示了这种表示的含义。

![img](http://neuralnetworksanddeeplearning.com/images/tikz17.png)

With these notations, the activation $a^l_j$ of the $j^{\rm th}$ neuron in the $l^{\rm th}$ layer is related to the activations in the $(l-1)^{\rm th}$ layer by the equation (compare Equation (4) and surrounding discussion in the last chapter)

有了这些表示，第 $l^{\rm th}$ 层第 $j^{\rm th}$ 个神经元的激活值 $a^l_j$  就和第 $(l-1)^{\rm th}$ 层的激活值通过方程关联起来了（对比方程(4)和第 1 章的讨论）
$$
\begin{eqnarray} 
  a^{l}_j = \sigma\left( \sum_k w^{l}_{jk} a^{l-1}_k + b^l_j \right),
\tag{23}\end{eqnarray}
$$

where the sum is over all neurons $k$ in the $(l-1)^{\rm th}$ layer. To rewrite this expression in a matrix form we define a *weight matrix* $w^l$ for each layer, $l$. The entries of the weight matrix $w^l$ are just the weights connecting to the $l^{\rm th}$ layer of neurons, that is, the entry in the $j^{\rm th}$ row and $k^{\rm th}$ column is $w^l_{jk}$. Similarly, for each layer $l$ we define a *bias vector*, $b^l$. You can probably guess how this works - the components of the bias vector are just the values $b^l_j$, one component for each neuron in the $l^{\rm th}$ layer. And finally, we define an activation vector $a^l$ whose components are the activations $a^l_j$.

其中求和是对第 $(l-1)^{\rm th}$ 层的所有 $k$ 个神经元进行的。为了以矩阵的形式重写该表达式，我们对层 $l$ 定义一个权重矩阵 $w^l$，$w^l$ 的元素正是连接到第 $l$ 层神经元的权重，更确切地说，第 $j$ 行第 $k$ 列的元素是 $w^l_{jk}$。类似地，对层 $l$ 定义一个偏置向量 $b^l$。由此可推导出偏置向量的分量其实就是前面给出的 $b^l_j$，每个元素对应第 $l^{\rm th}$ 层的每个神经元。然后定义激活向量 $a^l$，其分量是激活值 $a^l_j$。

The last ingredient we need to rewrite (23) in a matrix form is the idea of vectorizing a function such as $\sigma$. We met vectorization briefly in the last chapter, but to recap, the idea is that we want to apply a function such as $\sigma$ to every element in a vector $v$. We use the obvious notation $\sigma(v)$ to denote this kind of elementwise application of a function. That is, the components of $\sigma(v)$ are just $\sigma(v)_j = \sigma(v_j)$. As an example, if we have the function $f(x) = x^2$ then the vectorized form of $f$ has the effect

最后需要引入向量化函数（比如 $\sigma$）来按照矩阵形式重写方程(23)。第 1 章提到过向量化，其含义就是对向量 $v$ 中的每个元素应用函数（比如 $\sigma$）。我们使用 $\sigma(v)$ 来表示按元素应用函数。所以，$\sigma(v)$ 的每个元素满足 $\sigma(v)_j = \sigma(v_j)$。如果函数是 $f(x) = x^2$，那么向量化的 $f$ 作用如下：
$$
\begin{eqnarray}
  f\left(\left[ \begin{array}{c} 2 \\ 3 \end{array} \right] \right)
  = \left[ \begin{array}{c} f(2) \\ f(3) \end{array} \right]
  = \left[ \begin{array}{c} 4 \\ 9 \end{array} \right],
\tag{24}\end{eqnarray}
$$

that is, the vectorized $f$ just squares every element of the vector.

With these notations in mind, Equation (23) can be rewritten in the beautiful and compact vectorized form

也就是说，向量化的 $f$ 仅对向量的每个元素进行平方运算。

有了这些表示，方程(23)就可以写成简洁的向量形式了，如下所示：

$$
\begin{eqnarray} 
  a^{l} = \sigma(w^l a^{l-1}+b^l).
\tag{25}\end{eqnarray}
$$

This expression gives us a much more global way of thinking about how the activations in one layer relate to activations in the previous layer: we just apply the weight matrix to the activations, then add the bias vector, and finally apply the $\sigma$ function*. That global view is often easier and more succinct (and involves fewer indices!) than the neuron-by-neuron view we've taken to now. Think of it as a way of escaping index hell, while remaining precise about what's going on. The expression is also useful in practice, because most matrix libraries provide fast ways of implementing matrix multiplication, vector addition, and vectorization. Indeed, the [code](http://neuralnetworksanddeeplearning.com/chap1.html#implementing_our_network_to_classify_digits) in the last chapter made implicit use of this expression to compute the behaviour of the network.

该表达式让我们能够以全局视角考虑每层的激活值和前一层激活值的关联方式：我们仅仅把权重矩阵应用于激活值，然后加上一个偏置向量，最后应用 $\sigma$ 函数*。这种全局视角比神经元层面的视角更简洁（没有用索引下标）。这样做既保证了清晰表达，又避免了使用下标。在实践中，表达式同样很有用，因为大多数矩阵库提供了实现矩阵乘法、向量加法和向量化的快捷方法。实际上，第 1 章的代码隐式地使用了这种表达式来计算神经网络的输出。

> *By the way, it's this expression that motivates the quirk in the $w^l_{jk}$ notation mentioned earlier. If we used $j$ to index the input neuron, and $k$ to index the output neuron, then we'd need to replace the weight matrix in Equation (25) by the transpose of the weight matrix. That's a small change, but annoying, and we'd lose the easy simplicity of saying (and thinking) "apply the weight matrix to the activations".
>
> 其实，这就是不使用之前的下标表示（$w^l_{jk}$）的初因。如果用 $j$ 来索引输入神经元，用 $k$ 索引输出神经元，那么在方程(25)中需要对这里的矩阵进行转置。这个小的改变会带来麻烦，本可以简单地表述为“将权重矩阵应用于激活值”。

When using Equation (25) to compute $a^l$, we compute the intermediate quantity $z^l \equiv w^l a^{l-1}+b^l$ along the way. This quantity turns out to be useful enough to be worth naming: we call $z^l$ the *weighted input* to the neurons in layer $l$. We'll make considerable use of the weighted input $z^l$ later in the chapter. Equation (25) is sometimes written in terms of the weighted input, as $a^l = \sigma(z^l)$. It's also worth noting that $z^l$ has components $z^l_j = \sum_k w^l_{jk} a^{l-1}_k+b^l_j$, that is, $z^l_j$ is just the weighted input to the activation function for neuron $j$ in layer $l$.

在使用方程(25)计算 $a^l$的过程中，我们计算了中间量 $z^l \equiv w^l a^{l-1}+b^l$。这个中间量其实非常有用：我们将 $z^l$ 称作第 $l$ 层神经元的带权输入，稍后深入探究。方程(25)有时会写成带权输入的形式：$a^l = \sigma(z^l)$。此外，$z^l$ 的分量为 $z^l_j = \sum_k w^l_{jk} a^{l-1}_k+b^l_j$，其实 $z^l_j$ 就是第 $l$ 层第 $j$ 个神经元的激活函数的带权输入。

### 2.2 [The two assumptions we need about the cost function](http://neuralnetworksanddeeplearning.com/chap2.html#the_two_assumptions_we_need_about_the_cost_function)

The goal of backpropagation is to compute the partial derivatives $\partial C / \partial w$ and $\partial C / \partial b$ of the cost function $C$ with respect to any weight $w$ or bias $b$ in the network. For backpropagation to work we need to make two main assumptions about the form of the cost function. Before stating those assumptions, though, it's useful to have an example cost function in mind. We'll use the quadratic cost function from last chapter (c.f. Equation (6)). In the notation of the last section, the quadratic cost has the form

反向传播用于计算代价函数 $C$ 关于 $w$ 和 $b$ 的偏导数 $\partial C / \partial w$ 和 $\partial C / \partial b$。为了利用反向传播，需要针对代价函数做出两个主要假设。在此之前，先看一个具体的代价函数。我们会使用第 1 章中的二次代价函数，参见方程(6)。按照前面给出的表示，二次代价函数的形式如下：
$$
\begin{eqnarray}
  C = \frac{1}{2n} \sum_x \|y(x)-a^L(x)\|^2,
\tag{26}\end{eqnarray}
$$

where: $n$ is the total number of training examples; the sum is over individual training examples, $x$; $y = y(x)$ is the corresponding desired output; $L$ denotes the number of layers in the network; and $a^L = a^L(x)$ is the vector of activations output from the network when $x$ is input.

其中 $n$ 是训练样本的总数，求和运算遍历了训练样本 $x$，$y = y(x)$ 是对应的目标输出，$L$ 表示神经网络的层数，$a^L = a^L(x)$ 是当输入为 $x$ 时神经网络输出的激活向量。

> $a^L(x)$ 是模型对输入 $x$ 的最终预测值

**Okay, so what assumptions do we need to make about our cost function, $C$, in order that backpropagation can be applied**? The **first assumption** we need is that the cost function can be written as an average $C = \frac{1}{n} \sum_x C_x$ over cost functions $C_x$ for individual training examples, $x$. This is the case for the quadratic cost function, where the cost for a single training example is $C_x = \frac{1}{2} \|y-a^L \|^2$. This assumption will also hold true for all the other cost functions we'll meet in this book.

**为了应用反向传播，需要对代价函数 $C$ 做出什么前提假设呢**？<u>第一个假设是代价函数可以写成在每个训练样本 $x$ 上的代价函数 $C_x$ 的均值</u>，即 $C = \frac{1}{n} \sum_x C_x$。这是关于二次代价函数的例子，对于其中每个单独的训练样本，其代价是 $C_x = \frac{1}{2} \|y-a^L \|^2$。对于书中提到的其他代价函数，该假设也成立。

The reason we need this assumption is because what backpropagation actually lets us do is compute the partial derivatives $\partial C_x / \partial w$ and $\partial C_x / \partial b$ for a single training example. We then recover $\partial C / \partial w$ and $\partial C / \partial b$ by averaging over training examples. In fact, with this assumption in mind, we'll suppose the training example $x$ has been fixed, and drop the $x$ subscript, writing the cost $C_x$ as $C$. We'll eventually put the $x$ back in, but for now it's a notational nuisance that is better left implicit.

需要这个假设的原因是反向传播实际上是对单独的训练样本计算了  $\partial C_x / \partial w$ 和  $\partial C_x / \partial b$，然后在所有训练样本上进行平均得到 $\partial C / \partial w$ 和 $\partial C / \partial b$ 。实际上，基于该假设，训练样本 $x$ 相当于固定了，丢掉了下标，将代价函数 $C_x$ 写成了 $C$。最终我们会把下标加上，但现在这样做是为了简化表示。

The **second assumption** we make about the cost is that it can be written as a function of the outputs from the neural network:

<u>第二个假设就是代价函数可以写成神经网络输出的函数</u>，如图 2-3 所示：

![img](http://neuralnetworksanddeeplearning.com/images/tikz18.png)

For example, the quadratic cost function satisfies this requirement, since the quadratic cost for a single training example $x$ may be written as

例如二次代价函数满足该要求，因为对于单独的训练样本 $x$，其二次代价函数可以写成：
$$
\begin{eqnarray}
  C = \frac{1}{2} \|y-a^L\|^2 = \frac{1}{2} \sum_j (y_j-a^L_j)^2,
\tag{27}\end{eqnarray}
$$

and thus is a function of the output activations. Of course, this cost function also depends on the desired output $y$, and you may wonder why we're not regarding the cost also as a function of $y$. Remember, though, that the input training example $x$ is fixed, and so the output $y$ is also a fixed parameter. In particular, it's not something we can modify by changing the weights and biases in any way, i.e., it's not something which the neural network learns. And so it makes sense to regard $C$ as a function of the output activations $a^L$ alone, with $y$ merely a parameter that helps define that function.

这是关于输出激活值的函数。当然，该代价函数还依赖目标输出 $y$，你可能疑惑为什么不把代价函数也看作关于 $y$ 的函数。记住，输入的训练样本 $x$ 是固定的，所以输出 $y$ 也是固定参数，尤其无法通过随意改变权重和偏置来改变它，即这不是神经网络学习的对象。所以，把 $C$ 看成仅有输出激活值 $a^L$ 的函数才是合理的，$y$ 仅是协助定义函数的参数。

### 2.3 [The Hadamard product, $s \odot t$](http://neuralnetworksanddeeplearning.com/chap2.html#the_hadamard_product_$s_\odot_t$)

The backpropagation algorithm is based on common linear algebraic operations - things like vector addition, multiplying a vector by a matrix, and so on. But one of the operations is a little less commonly used. In particular, suppose $s$ and $t$ are two vectors of the same dimension. Then we use $s \odot t$ to denote the *element wise* product of the two vectors. Thus the components of $s \odot t$ are just $(s \odot t)_j = s_j t_j$. As an example,

反向传播算法基于常规的线性代数运算，比如向量加法、向量矩阵乘法等，但是有一个运算不太常用。假设 $s$ 和 $t$是两个维度相同的向量，那么 $s \odot t$ 表示按元素的乘积。所以 $s \odot t$ 的元素就是 $(s \odot t)_j = s_j t_j$，举例如下：
$$
\begin{eqnarray}
\left[\begin{array}{c} 1 \\ 2 \end{array}\right] 
  \odot \left[\begin{array}{c} 3 \\ 4\end{array} \right]
= \left[ \begin{array}{c} 1 * 3 \\ 2 * 4 \end{array} \right]
= \left[ \begin{array}{c} 3 \\ 8 \end{array} \right].
\tag{28}\end{eqnarray}
$$

This kind of element wise multiplication is sometimes called the *Hadamard product* or *Schur product*. We'll refer to it as the Hadamard product. Good matrix libraries usually provide fast implementations of the Hadamard product, and that comes in handy when implementing backpropagation.

这种按元素相乘有时称作**阿达马积**或**舒尔积**，本书采用前者。优秀的矩阵库通常会提供阿达马积的快速实现，在实现反向传播时易于使用。

### 2.4 [The four fundamental equations behind backpropagation](http://neuralnetworksanddeeplearning.com/chap2.html#the_four_fundamental_equations_behind_backpropagation)

Backpropagation is about understanding how changing the weights and biases in a network changes the cost function. Ultimately, this means computing the partial derivatives $\partial C / \partial w^l_{jk}$ and $\partial C / \partial b^l_j$. But to compute those, we first introduce an intermediate quantity, $\delta^l_j$, which we call the *error* in the $j^{\rm th}$ neuron in the $l^{\rm th}$ layer. Backpropagation will give us a procedure to compute the error $\delta^l_j$, and then will relate $\delta^l_j$ to $\partial C / \partial w^l_{jk}$ and $\partial C / \partial b^l_j$.

To understand how the error is defined, imagine there is a demon in our neural network:

其实反向传播考量的是如何更改权重和偏置以控制代价函数，其终极含义就是计算偏导数 $\partial C / \partial w^l_{jk}$ 和 $\partial C / \partial b^l_j$。为了计算这些值，首先需要引入中间量 $\delta^l_j$，它是的误差。**反向传播将给出计算误差 $\delta^l_j$ 的流程，然后将其与 $\partial C / \partial w^l_{jk}$ 和 $\partial C / \partial b^l_j$ 联系起来**。

为了说明误差是如何定义的，设想神经网络中有个捣乱的家伙，如下图所示：

![img](http://neuralnetworksanddeeplearning.com/images/tikz19.png)

The demon sits at the $j^{\rm th}$ neuron in layer ll. As the input to the neuron comes in, the demon messes with the neuron's operation. It adds a little change $\Delta z^l_j$ to the neuron's weighted input, so that instead of outputting $\sigma(z^l_j)$, the neuron instead outputs $\sigma(z^l_j+\Delta z^l_j)$. This change propagates through later layers in the network, finally causing the overall cost to change by an amount $\frac{\partial C}{\partial z^l_j} \Delta z^l_j$.

这个家伙在第 $l^{\rm th}$ 层的第 $j^{\rm th}$ 个神经元上。当输入进来时，它会扰乱神经元的操作。它会在神经元的带权输入上增加很小的变化 $\Delta z^l_j$，使得神经元输出由 $\sigma(z^l_j)$ 变成 $\sigma(z^l_j+\Delta z^l_j)$。这个变化会向后面的层传播，最终导致整个代价发生 $\frac{\partial C}{\partial z^l_j} \Delta z^l_j$ 的改变。

Now, this demon is a good demon, and is trying to help you improve the cost, i.e., they're trying to find a $\Delta z^l_j$ which makes the cost smaller. Suppose $\frac{\partial C}{\partial z^l_j}$ has a large value (either positive or negative). Then the demon can lower the cost quite a bit by choosing $\Delta z^l_j$ to have the opposite sign to $\frac{\partial C}{\partial z^l_j}$. By contrast, if $\frac{\partial C}{\partial z^l_j}$ is close to zero, then the demon can't improve the cost much at all by perturbing the weighted input $z^l_j$. So far as the demon can tell, the neuron is already pretty near optimal*. And so there's a heuristic sense in which $\frac{\partial C}{\partial z^l_j}$ is a measure of the error in the neuron.

Motivated by this story, we define the error $\delta^l_j$ of neuron $j$ in layer $l$ by:

现在，这个家伙变好了，想帮忙优化代价函数，它试着寻找能让代价更小的 $\Delta z^l_j$。假设 $\frac{\partial C}{\partial z^l_j}$ 有一个很大的值（或正或负）。这个家伙可以通过选择跟 $\frac{\partial C}{\partial z^l_j}$ 符号相反的 $\Delta z^l_j$ 来缩小代价。如果 $\frac{\partial C}{\partial z^l_j}$ 接近 0，那么它并不能通过扰动带权输入 $z^l_j$ 来缩小太多代价。对它而言，这时神经元已经很接近最优了*。这里可以得出具有启发性的认识——$\frac{\partial C}{\partial z^l_j}$ 是对神经元误差的度量。

按照前面的描述，把第 $l^{\rm th}$ 层第 $j^{\rm th}$ 个神经元上的误差  $\delta^l_j$ 定义为：

$$
\begin{eqnarray} 
  \delta^l_j \equiv \frac{\partial C}{\partial z^l_j}.
\tag{29}\end{eqnarray}
$$

> *This is only the case for small changes $\Delta z^l_j$, of course. We'll assume that the demon is constrained to make such small changes.
>
> 这里需要注意的是，只有在 $\Delta z^l_j$ 很小时才满足，需要假设这个家伙只能进行微调。

As per our usual conventions, we use $\delta^l$ to denote the vector of errors associated with layer $l$. Backpropagation will give us a way of computing $\delta^l$ for every layer, and then relating those errors to the quantities of real interest, $\partial C / \partial w^l_{jk}$ and $\partial C / \partial b^l_j$.

按照惯例，用 $\delta^l$ 表示与第 $l$ 层相关的误差向量。可以利用反向传播计算每一层的 $\delta^l$，然后将这些误差与实际需要的量 $\partial C / \partial w^l_{jk}$ 和 $\partial C / \partial b^l_j$ 关联起来。

You might wonder why the demon is changing the weighted input $z^l_j$. Surely it'd be more natural to imagine the demon changing the output activation $a^l_j$, with the result that we'd be using $\frac{\partial   C}{\partial a^l_j}$ as our measure of error. In fact, if you do this things work out quite similarly to the discussion below. But it turns out to make the presentation of backpropagation a little more algebraically complicated. So we'll stick with $\delta^l_j = \frac{\partial C}{\partial z^l_j}$ as our measure of error*.

你可能想知道这个家伙为何改变带权输入 $z^l_j$。把它想象成改变输出激活值 $a^l_j$ 肯定更自然，这样就可以使用 $\frac{\partial   C}{\partial a^l_j}$ 度量误差了。这样做的话，其实和下面要讨论的差不多，但前面的方法会让反向传播在代数运算上变得比较复杂，所以这里使用 $\delta^l_j = \frac{\partial C}{\partial z^l_j}$ 作为对误差的度量

> *In classification problems like MNIST the term "error" is sometimes used to mean the classification failure rate. E.g., if the neural net correctly classifies 96.0 percent of the digits, then the error is 4.0 percent. Obviously, this has quite a different meaning from our $\delta$ vectors. In practice, you shouldn't have trouble telling which meaning is intended in any given usage.
>
> 在分类问题中，误差有时会用作分类的错误率。如果神经网络分类的正确率为 96.0%，那么其误差就是 4.0%。显然，这和前面提到的误差相差较大。在实际应用中，这两种含义易于区分。

**Plan of attack:** Backpropagation is based around four fundamental equations. Together, those equations give us a way of computing both the error $\delta^l$ and the gradient of the cost function. I state the four equations below. Be warned, though: you shouldn't expect to instantaneously assimilate the equations. Such an expectation will lead to disappointment. In fact, the backpropagation equations are so rich that understanding them well requires considerable time and patience as you gradually delve deeper into the equations. The good news is that such patience is repaid many times over. And so the discussion in this section is merely a beginning, helping you on the way to a thorough understanding of the equations.

**解决方案**：反向传播基于 4 个基本方程，利用它们可以计算误差 $\delta^l$ 和代价函数的梯度。下面列出这 4 个方程，但请注意，你不需要立刻理解这些方程。实际上，反向传播方程的内容很多，完全理解相当需要时间和耐心。当然，这样的付出有着巨大的回报。因此，对这些内容的讨论仅仅是正确掌握这些方程的开始。

Here's a preview of the ways we'll delve more deeply into the equations later in the chapter: I'll [give a short proof of the equations](http://neuralnetworksanddeeplearning.com/chap2.html#proof_of_the_four_fundamental_equations_(optional)), which helps explain why they are true; we'll [restate the equations](http://neuralnetworksanddeeplearning.com/chap2.html#the_backpropagation_algorithm) in algorithmic form as pseudocode, and [see how](http://neuralnetworksanddeeplearning.com/chap2.html#the_code_for_backpropagation) the pseudocode can be implemented as real, running Python code; and, in [the final section of the chapter](http://neuralnetworksanddeeplearning.com/chap2.html#backpropagation_the_big_picture), we'll develop an intuitive picture of what the backpropagation equations mean, and how someone might discover them from scratch. Along the way we'll return repeatedly to the four fundamental equations, and as you deepen your understanding those equations will come to seem comfortable and, perhaps, even beautiful and natural.

探讨这些方程的流程如下：首先[给出这些方程的简短证明](http://neuralnetworksanddeeplearning.com/chap2.html#proof_of_the_four_fundamental_equations_(optional))，然后以伪代码的方式给出[这些方程的算法表示](http://neuralnetworksanddeeplearning.com/chap2.html#the_backpropagation_algorithm)，并展示如何将这些伪代码[转化成可执行的 Python 代码](http://neuralnetworksanddeeplearning.com/chap2.html#the_code_for_backpropagation)。本章[最后](http://neuralnetworksanddeeplearning.com/chap2.html#backpropagation_the_big_picture)将直观展现反向传播方程的含义，以及如何从零开始认识这个规律。根据该方法，我们会经常提及这 4 个基本方程。随着理解的加深，这些方程看起来会更合理、更美妙、更自然。

**An equation for the error in the output layer, $\delta^L$:** The components of $\delta^L$ are given by

**关于输出层误差的方程**，$\delta^L$ 分量表示为：
$$
\begin{eqnarray} 
  \delta^L_j = \frac{\partial C}{\partial a^L_j} \sigma'(z^L_j).
\tag{BP1}\end{eqnarray}
$$

This is a very natural expression. The first term on the right, $\partial C / \partial a^L_j$, just measures how fast the cost is changing as a function of the $j^{\rm th}$ output activation. If, for example, $C$ doesn't depend much on a particular output neuron, $j$, then $\delta^L_j$ will be small, which is what we'd expect. The second term on the right, $\sigma'(z^L_j)$, measures how fast the activation function $\sigma$ is changing at $z^L_j$.

这个表达式非常自然。右边第一项 $\partial C / \partial a^L_j$ 表示代价随第 $j^{\rm th}$  个输出激活值的变化而变化的速度。假如 $C$ 不太依赖特定的输出神经元 $j$，那么 $\delta^L_j$ 就会很小，这也是我们想要的效果。右边第二项 $\sigma'(z^L_j)$, 描述了激活函数 $\sigma$ 在 $z^L_j$ 处的变化速度。

Notice that everything in (BP1) is easily computed. In particular, we compute $z^L_j$ while computing the behaviour of the network, and it's only a small additional overhead to compute $\sigma'(z^L_j)$. The exact form of $\partial C / \partial a^L_j$ will, of course, depend on the form of the cost function. However, provided the cost function is known there should be little trouble computing $\partial C / \partial a^L_j$. For example, if we're using the quadratic cost function then $C = \frac{1}{2} \sum_j (y_j-a^L_j)^2$, and so $\partial C / \partial a^L_j = (a_j^L-y_j)$, which obviously is easily computable.

值得注意的是，方程(BP1)中的每个部分都很好计算。具体地说，在计算神经网络行为时计算 $z^L_j$，仅需一点点额外工作就可以计算 $\sigma'(z^L_j)$.。当然，$\partial C / \partial a^L_j$ 取决于代价函数的形式。然而，给定代价函数，计算 $\partial C / \partial a^L_j$ 就没有什么大问题了。如果使用二次代价函数，那么 $C = \frac{1}{2} \sum_j (y_j-a^L_j)^2$，所以 $\partial C / \partial a^L_j = (a_j^L-y_j)$，显然很容易计算。

Equation (BP1) is a componentwise expression for $\delta^L$. It's a perfectly good expression, but not the matrix-based form we want for backpropagation. However, it's easy to rewrite the equation in a matrix-based form, as

对 $\delta^L$ 来说，方程(BP1)是个分量形式的表达式。这个表达式非常好，但不是理想形式（我们希望用矩阵表示）。以矩阵形式重写方程其实很简单：
$$
\begin{eqnarray} 
  \delta^L = \nabla_a C \odot \sigma'(z^L).
\tag{BP1a}\end{eqnarray}
$$

Here, $\nabla_a C$ is defined to be a vector whose components are the partial derivatives $\partial C / \partial a^L_j$. You can think of $\nabla_a C$ as expressing the rate of change of $C$ with respect to the output activations. It's easy to see that Equations (BP1a) and (BP1) are equivalent, and for that reason from now on we'll use (BP1) interchangeably to refer to both equations. As an example, in the case of the quadratic cost we have $\nabla_a C = (a^L-y)$, and so the fully matrix-based form of (BP1) becomes

其中的 $\nabla_a C$ 定义为一个向量，其分量是偏导数 $\partial C / \partial a^L_j$。可以把 $\nabla_a C$ 看作 $C$ 关于输出激活值的变化速度。显然，方程(BP1)和方程(BP1a)等价，所以下面用方程(BP1)表示这两个方程。例如对于二次代价函数，有 $\nabla_a C = (a^L-y)$，所以方程(BP1)的整个矩阵形式如下：
$$
\begin{eqnarray} 
  \delta^L = (a^L-y) \odot \sigma'(z^L).
\tag{30}\end{eqnarray}
$$

As you can see, everything in this expression has a nice vector form, and is easily computed using a library such as Numpy.

如上所示，该方程中的每一项都有很好的向量形式，因此便于使用 NumPy 或其他矩阵库进行计算。

**An equation for the error $\delta^l$ in terms of the error in the next layer, $\delta^{l+1}$:** In particular

使用下一层的误差 $\delta^{l+1}$ 来表示当前层的误差 $\delta^l$，有：
$$
\begin{eqnarray} 
  \delta^l = ((w^{l+1})^T \delta^{l+1}) \odot \sigma'(z^l),
\tag{BP2}\end{eqnarray}
$$

where $(w^{l+1})^T$ is the transpose of the weight matrix $w^{l+1}$ for the $(l+1)^{\rm th}$ layer. This equation appears complicated, but each element has a nice interpretation. Suppose we know the error $\delta^{l+1}$ at the $(l+1)^{\rm th}$ layer. When we apply the transpose weight matrix, $(w^{l+1})^T$, we can think intuitively of this as moving the error *backward* through the network, giving us some sort of measure of the error at the output of the $l^{\rm th}$ layer. We then take the Hadamard product $\odot \sigma'(z^l)$. This moves the error backward through the activation function in layer $l$, giving us the error $\delta^l$ in the weighted input to layer $l$.

其中 $(w^{l+1})^T$ 是第 $(l+1)^{\rm th}$ 层权重矩阵 $w^{l+1}$  的转置。该方程看上去有些复杂，但每个组成元素都解释得通。假设我们知道第 $(l+1)^{\rm th}$ 层的误差 $\delta^{l+1}$，当应用转置的权重矩阵 $(w^{l+1})^T$ 时，可git以凭直觉把它看作在沿着神经网络反向移动误差，以此度量第 $l^{th}$ 层输出的误差；然后计算阿达马积 $\odot \sigma'(z^l)$，这会让误差通过第 $l$ 层的激活函数反向传播回来并给出第 $l$ 层的带权输入的误差 $\delta^l$。

By combining (BP2) with (BP1) we can compute the error $\delta^l$ for any layer in the network. We start by using (BP1) to compute $\delta^L$, then apply Equation (BP2) to compute $\delta^{L-1}$, then Equation (BP2) again to compute $\delta^{L-2}$, and so on, all the way back through the network.

通过组合(BP1)和(BP2)，可以计算任何层的误差 $\delta^l$。首先使用方程(BP1)计算 $\delta^L$，然后使用方程(BP2)计算 $\delta^{L-1}$，接着再次用方程(BP2)计算 $\delta^{L-2}$，如此一步一步地在神经网络中反向传播。

**An equation for the rate of change of the cost with respect to any bias in the network:** In particular:

对于神经网络中的任意偏置，代价函数的变化率如下：
$$
\begin{eqnarray}  \frac{\partial C}{\partial b^l_j} =
  \delta^l_j.
\tag{BP3}\end{eqnarray}
$$

That is, the error $\delta^l_j$ is *exactly equal* to the rate of change $\partial C / \partial b^l_j$. This is great news, since (BP1) and (BP2) have already told us how to compute $\delta^l_j$. We can rewrite (BP3) in shorthand as

也就是说，误差 [插图] 和变化率 [插图] 完全一致。该性质很棒，由于(BP1)和(BP2)给出了计算 [插图] 的方式，因此可以将(BP3)简写为：
$$
\begin{eqnarray}
  \frac{\partial C}{\partial b} = \delta,
\tag{31}\end{eqnarray}
$$

where it is understood that $\delta$ is being evaluated at the same neuron as the bias $b$.

其中 [插图] 和偏置 [插图] 都是针对同一个神经元的。

**An equation for the rate of change of the cost with respect to any weight in the network:** In particular:

**对于神经网络中的任意权重，代价函数的变化率如下**：
$$
\begin{eqnarray}
  \frac{\partial C}{\partial w^l_{jk}} = a^{l-1}_k \delta^l_j.
\tag{BP4}\end{eqnarray}
$$

This tells us how to compute the partial derivatives $\partial C / \partial w^l_{jk}$ in terms of the quantities $\delta^l$ and $a^{l-1}$, which we already know how to compute. The equation can be rewritten in a less index-heavy notation as

由此可以计算偏导数 [插图]，其中 [插图] 和 [插图] 这些量的计算方式已经给出，因此可以用更少的下标重写方程，如下所示：
$$
\begin{eqnarray}  \frac{\partial
    C}{\partial w} = a_{\rm in} \delta_{\rm out},
\tag{32}\end{eqnarray}
$$

where it's understood that $a_{\rm in}$ is the activation of the neuron input to the weight $w$, and $\delta_{\rm out}$ is the error of the neuron output from the weight $w$. Zooming in to look at just the weight $w$, and the two neurons connected by that weight, we can depict this as:

其中 [插图] 是输入到权重 [插图] 的神经元的激活值，[插图] 是权重 [插图] 输出的神经元的误差。仔细看看权重 [插图]，还有与之相连的两个神经元，如图 2-5 所示。

![img](http://neuralnetworksanddeeplearning.com/images/tikz20.png)

A nice consequence of Equation (32) is that when the activation $a_{\rm in}$ is small, $a_{\rm in} \approx 0$, the gradient term $\partial C / \partial w$ will also tend to be small. In this case, we'll say the weight *learns slowly*, meaning that it's not changing much during gradient descent. In other words, one consequence of (BP4) is that weights output from low-activation neurons learn slowly.

方程(32)的一个优点是，如果激活值 [插图] 很小，即 [插图]，那么梯度 [插图] 的值也会很小。这意味着权重学习缓慢，受梯度下降的影响不大。换言之，方程(BP4)的一个结果就是小激活值神经元的权重学习会非常缓慢。

There are other insights along these lines which can be obtained from (BP1)-(BP4). Let's start by looking at the output layer. Consider the term $\sigma'(z^L_j)$ in (BP1). Recall from the [graph of the sigmoid function in the last chapter](http://neuralnetworksanddeeplearning.com/chap1.html#sigmoid_graph) that the $\sigma$ function becomes very flat when $\sigma(z^L_j)$ is approximately 0 or 1. When this occurs we will have $\sigma'(z^L_j) \approx 0$. And so the lesson is that a weight in the final layer will learn slowly if the output neuron is either low activation ($\approx 0$) or high activation ($\approx 1$). In this case it's common to say the output neuron has *saturated* and, as a result, the weight has stopped learning (or is learning slowly). Similar remarks hold also for the biases of output neuron.

以上 4 个基本方程还有其他地方值得研究。下面从输出层开始，先看看(BP1)中的项 [插图]。回顾一下sigmoid 函数的图像（详见第 1 章），当 [插图] 近似为0或1时，sigmoid 函数变得非常平缓，这时 [插图]。因此，如果输出神经元处于小激活值（约为 0）或者大激活值（约为 1）时，最终层的权重学习会非常缓慢。这时可以说输出神经元已经饱和了，并且，权重学习也会终止（或者学习非常缓慢），输出神经元的偏置也与之类似。

We can obtain similar insights for earlier layers. In particular, note the $\sigma'(z^l)$ term in (BP2). This means that $\delta^l_j$ is likely to get small if the neuron is near saturation. And this, in turn, means that any weights input to a saturated neuron will learn slowly*.

前面的层也有类似的特点，尤其注意(BP2)中的项 [插图]，这表示如果神经元已经接近饱和，那么 [插图] 很可能变小。这就导致输入到已饱和神经元的任何权重都学习缓慢*。

> *This reasoning won't hold if ${w^{l+1}}^T   \delta^{l+1}$ has large enough entries to compensate for the smallness of $\sigma'(z^l_j)$. But I'm speaking of the general tendency.
>
> 如果 [插图] 足够大，能够弥补 [插图] 的话，这里的推导就不成立了，但上面是常见的情形。

Summing up, we've learnt that a weight will learn slowly if either the input neuron is low-activation, or if the output neuron has saturated, i.e., is either high- or low-activation.

总结一下，前面讲到，如果输入神经元激活值很小，或者输出神经元已经饱和，权重学习会很缓慢。

None of these observations is too greatly surprising. Still, they help improve our mental model of what's going on as a neural network learns. Furthermore, we can turn this type of reasoning around. The four fundamental equations turn out to hold for any activation function, not just the standard sigmoid function (that's because, as we'll see in a moment, the proofs don't use any special properties of $\sigma$). And so we can use these equations to *design* activation functions which have particular desired learning properties. As an example to give you the idea, suppose we were to choose a (non-sigmoid) activation function $\sigma$ so that $\sigma'$ is always positive, and never gets close to zero. That would prevent the slow-down of learning that occurs when ordinary sigmoid neurons saturate. Later in the book we'll see examples where this kind of modification is made to the activation function. Keeping the four equations (BP1)-(BP4) in mind can help explain why such modifications are tried, and what impact they can have.

这些观测并不出乎意料，它们有助于完善神经网络学习背后的思维模型，而且，这种推断方式可以挪用他处。4 个基本方程其实对任何激活函数都是成立的（稍后将证明，推断本身与任何具体的代价函数无关），因此可以使用这些方程来设计有特定学习属性的激活函数。例如我们准备找一个非 sigmoid 激活函数 [插图]，使得[插图] 总为正，而且不会趋近 0。这可以避免原始的sigmoid 神经元饱和时学习速度下降的问题。后文会探讨对激活函数的这类修改。牢记这 4 个基本方程（见图2-6）有助于了解为何进行某些尝试，以及这些尝试的影响。

![img](http://neuralnetworksanddeeplearning.com/images/tikz21.png)

[Problem](http://neuralnetworksanddeeplearning.com/chap2.html#problem_543309)

Alternate presentation of the equations of backpropagation:  I've stated the equations of backpropagation (notably  (BP1) and (BP2) ) using the Hadamard product. This presentation may be disconcerting if you're unused to the Hadamard product. There's an alternative approach, based on conventional matrix multiplication, which some readers may find enlightening. 

(1) Show that (BP1) may be rewritten as

**反向传播方程的另一种表示方式**：前面给出了使用阿达马积的反向传播方程，尤其是(BP1)和(BP2)。如果你对这种特殊的乘积不熟悉，可能会有一些困惑。还有一种表示方式——基于传统的矩阵乘法，某些读者可以从中获得启发。

(1) 证明(BP1)可以写成：
$$
\begin{eqnarray}
    \delta^L = \Sigma'(z^L) \nabla_a C,
  \tag{33}\end{eqnarray}
$$

where  $\Sigma'(z^L)$  is a square matrix whose diagonal entries are the values  $\sigma'(z^L_j)$, and whose off-diagonal entries are zero. Note that this matrix acts on $\nabla_a C$ by conventional matrix multiplication.

其中 [插图] 是一个方阵，其对角线的元素是[插图]，其他的元素均为 0。注意，该矩阵通过一般的矩阵乘法作用于 [插图]。

 (2) Show that (BP2) may be rewritten as

 (2) 证明(BP2)可以写成：
$$
\begin{eqnarray}
    \delta^l = \Sigma'(z^l) (w^{l+1})^T \delta^{l+1}.
  \tag{34}\end{eqnarray}
$$

(3) By combining observations (1) and (2) show that  

(3) 结合(1)和(2)证明：
$$
\begin{eqnarray}
    \delta^l = \Sigma'(z^l) (w^{l+1})^T \ldots \Sigma'(z^{L-1}) (w^L)^T 
    \Sigma'(z^L) \nabla_a C
  \tag{35}\end{eqnarray}
$$

For readers comfortable with matrix multiplication this equation may be easier to understand than (BP1) and (BP2)  The reason I've focused on (BP1)  and (BP2)  is because that approach turns out to be faster to implement numerically.

如果习惯于这种形式的矩阵乘法，会发现(BP1)和(BP2)更容易理解。本书坚持使用阿达马积的原因是其实现起来更快。

### 2.5 [Proof of the four fundamental equations (optional)](http://neuralnetworksanddeeplearning.com/chap2.html#proof_of_the_four_fundamental_equations_(optional))

We'll now prove the four fundamental equations (BP1)-(BP4). All four are consequences of the chain rule from multivariable calculus. If you're comfortable with the chain rule, then I strongly encourage you to attempt the derivation yourself before reading on.

Let's begin with Equation (BP1), which gives an expression for the output error, $\delta^L$. To prove this equation, recall that by definition

$$
\begin{eqnarray}
  \delta^L_j = \frac{\partial C}{\partial z^L_j}.
\tag{36}\end{eqnarray}
$$

Applying the chain rule, we can re-express the partial derivative above in terms of partial derivatives with respect to the output activations,

$$
\begin{eqnarray}
  \delta^L_j = \sum_k \frac{\partial C}{\partial a^L_k} \frac{\partial a^L_k}{\partial z^L_j},
\tag{37}\end{eqnarray}
$$

where the sum is over all neurons $k$ in the output layer. Of course, the output activation $a^L_k$ of the $k^{\rm th}$ neuron depends only on the weighted input $z^L_j$ for the $j^{\rm th}$ neuron when $k = j$. And so $\partial a^L_k / \partial z^L_j$ vanishes when $k \neq j$. As a result we can simplify the previous equation to

$$
\begin{eqnarray}
  \delta^L_j = \frac{\partial C}{\partial a^L_j} \frac{\partial a^L_j}{\partial z^L_j}.
\tag{38}\end{eqnarray}
$$

Recalling that $a^L_j = \sigma(z^L_j)$ the second term on the right can be written as $\sigma'(z^L_j)$, and the equation becomes

$$
\begin{eqnarray}
  \delta^L_j = \frac{\partial C}{\partial a^L_j} \sigma'(z^L_j),
\tag{39}\end{eqnarray}
$$
which is just (BP1), in component form.

Next, we'll prove (BP2), which gives an equation for the error $\delta^l$ in terms of the error in the next layer, $\delta^{l+1}$. To do this, we want to rewrite $\delta^l_j = \partial C / \partial z^l_j$ in terms of $\delta^{l+1}_k = \partial C / \partial z^{l+1}_k$. We can do this using the chain rule,

$$
\begin{eqnarray}
  \delta^l_j & = & \frac{\partial C}{\partial z^l_j} \tag{40}\\
  & = & \sum_k \frac{\partial C}{\partial z^{l+1}_k} \frac{\partial z^{l+1}_k}{\partial z^l_j} \tag{41}\\ 
  & = & \sum_k \frac{\partial z^{l+1}_k}{\partial z^l_j} \delta^{l+1}_k,
\tag{42}\end{eqnarray}
$$
where in the last line we have interchanged the two terms on the right-hand side, and substituted the definition of $\delta^{l+1}_k$. To evaluate the first term on the last line, note that

$$
\begin{eqnarray}
  z^{l+1}_k = \sum_j w^{l+1}_{kj} a^l_j +b^{l+1}_k = \sum_j w^{l+1}_{kj} \sigma(z^l_j) +b^{l+1}_k.
\tag{43}\end{eqnarray}
$$
Differentiating, we obtain

$$
\begin{eqnarray}
  \frac{\partial z^{l+1}_k}{\partial z^l_j} = w^{l+1}_{kj} \sigma'(z^l_j).
\tag{44}\end{eqnarray}
$$
Substituting back into (42) we obtain

$$
\begin{eqnarray}
  \delta^l_j = \sum_k w^{l+1}_{kj}  \delta^{l+1}_k \sigma'(z^l_j).
\tag{45}\end{eqnarray}
$$
This is just (BP2) written in component form.

The final two equations we want to prove are (BP3) and (BP4). These also follow from the chain rule, in a manner similar to the proofs of the two equations above. I leave them to you as an exercise.

[Exercise](http://neuralnetworksanddeeplearning.com/chap2.html#exercise_522523)

- Prove Equations (BP3) and (BP4).

  That completes the proof of the four fundamental equations of backpropagation. The proof may seem complicated. But it's really just the outcome of carefully applying the chain rule. A little less succinctly, we can think of backpropagation as a way of computing the gradient of the cost function by systematically applying the chain rule from multi-variable calculus. That's all there really is to backpropagation - the rest is details.

### 2.6 [The backpropagation algorithm](http://neuralnetworksanddeeplearning.com/chap2.html#the_backpropagation_algorithm)

The backpropagation equations provide us with a way of computing the gradient of the cost function. Let's explicitly write this out in the form of an algorithm:

1. **Input** $x$: Set the corresponding activation a1a1 for the input layer.
2. **Feedforward**: For each $l = 2, 3, \ldots, L$ compute $z^{l} = w^l a^{l-1}+b^l$ and $a^l = \sigma(z^l)$.
3. **Output error** $\delta^L$: Compute the vector $\delta^{L}   = \nabla_a C \odot \sigma'(z^L)$.
4. **Backpropagate the error**: For each $l = L-1, L-2,   \ldots, 2$ compute $\delta^{l} = ((w^{l+1})^T \delta^{l+1}) \odot   \sigma'(z^{l})$.
5. **Output**: The gradient of the cost function is given by $\frac{\partial C}{\partial w^l_{jk}} = a^{l-1}_k \delta^l_j$ and $\frac{\partial C}{\partial w^l_{jk}} = a^{l-1}_k \delta^l_j$.

Examining the algorithm you can see why it's called *back*propagation. We compute the error vectors $\delta^l$ backward, starting from the final layer. It may seem peculiar that we're going through the network backward. But if you think about the proof of backpropagation, the backward movement is a consequence of the fact that the cost is a function of outputs from the network. To understand how the cost varies with earlier weights and biases we need to repeatedly apply the chain rule, working backward through the layers to obtain usable expressions.

[Exercises](http://neuralnetworksanddeeplearning.com/chap2.html#exercises_675621)

- **Backpropagation with a single modified neuron** Suppose we modify a single neuron in a feedforward network so that the output from the neuron is given by $f(\sum_j w_j x_j + b)$, where $f$ is some function other than the sigmoid. How should we modify the backpropagation algorithm in this case?
- **Backpropagation with linear neurons** Suppose we replace the usual non-linear $\sigma$ function with $\sigma(z) = z$ throughout the network. Rewrite the backpropagation algorithm for this case.

As I've described it above, the backpropagation algorithm computes the gradient of the cost function for a single training example, $C = C_x$. In practice, it's common to combine backpropagation with a learning algorithm such as stochastic gradient descent, in which we compute the gradient for many training examples. In particular, given a mini-batch of $m$ training examples, the following algorithm applies a gradient descent learning step based on that mini-batch:

1. **Input a set of training examples**
2. **For each training example** $x$: Set the corresponding input activation ax,1ax,1, and perform the following steps:
   - **Feedforward**: For each $l = 2, 3, \ldots, L$ compute $z^{x,l} = w^l a^{x,l-1}+b^l$ and $a^{x,l} = \sigma(z^{x,l})$.
   - **Output error** $\delta^{x,L}$: Compute the vector $\delta^{x,L} = \nabla_a C_x \odot \sigma'(z^{x,L})$.
   - **Backpropagate the error:** For each $l = L-1, L-2,   \ldots, 2$ compute $\delta^{x,l} = ((w^{l+1})^T \delta^{x,l+1})  \odot \sigma'(z^{x,l})$.
3. Gradient descent: For each $l = L-1, L-2,   \ldots, 2$ update the weights according to the rule $w^l \rightarrow   w^l-\frac{\eta}{m} \sum_x \delta^{x,l} (a^{x,l-1})^T$, and the biases according to the rule $b^l \rightarrow b^l-\frac{\eta}{m}   \sum_x \delta^{x,l}$.

Of course, to implement stochastic gradient descent in practice you also need an outer loop generating mini-batches of training examples, and an outer loop stepping through multiple epochs of training. I've omitted those for simplicity.

### 2.7 [The code for backpropagation](http://neuralnetworksanddeeplearning.com/chap2.html#the_code_for_backpropagation)

Having understood backpropagation in the abstract, we can now understand the code used in the last chapter to implement backpropagation. Recall from [that chapter](http://neuralnetworksanddeeplearning.com/chap1.html#implementing_our_network_to_classify_digits) that the code was contained in the `update_mini_batch` and `backprop` methods of the `Network` class. The code for these methods is a direct translation of the algorithm described above. In particular, the `update_mini_batch` method updates the `Network`'s weights and biases by computing the gradient for the current `mini_batch` of training examples:

介绍完了抽象的反向传播理论，下面分析反向传播的实现代码。回顾第 1章的代码，需要研究 `Network` 类中的 `update_mini_batch` 方法和`backprop` 方法。这些方法的代码其实是前面所讲算法的翻版。其中`update_mini_batch` 方法通过为当前 `mini_batch` 中的训练样本计算梯度来更新 `Network` 的权重和偏置。

```python
class Network(object):
...
    def update_mini_batch(self, mini_batch, eta):
        """Update the network's weights and biases by applying
        gradient descent using backpropagation to a single mini batch.
        The "mini_batch" is a list of tuples "(x, y)", and "eta"
        is the learning rate."""
        nabla_b = [np.zeros(b.shape) for b in self.biases]
        nabla_w = [np.zeros(w.shape) for w in self.weights]
        for x, y in mini_batch:
            delta_nabla_b, delta_nabla_w = self.backprop(x, y)
            nabla_b = [nb+dnb for nb, dnb in zip(nabla_b, delta_nabla_b)]
            nabla_w = [nw+dnw for nw, dnw in zip(nabla_w, delta_nabla_w)]
        self.weights = [w-(eta/len(mini_batch))*nw 
                        for w, nw in zip(self.weights, nabla_w)]
        self.biases = [b-(eta/len(mini_batch))*nb 
                       for b, nb in zip(self.biases, nabla_b)]
```

Most of the work is done by the line `delta_nabla_b, delta_nabla_w = self.backprop(x, y)` which uses the `backprop` method to figure out the partial derivatives $\partial C_x / \partial b^l_j$ and $\partial C_x / \partial w^l_{jk}$. The `backprop` method follows the algorithm in the last section closely. There is one small change - we use a slightly different approach to indexing the layers. This change is made to take advantage of a feature of Python, namely the use of negative list indices to count backward from the end of a list, so, e.g., `l[-3]` is the third last entry in a list `l`. The code for `backprop` is below, together with a few helper functions, which are used to compute the $\sigma$ function, the derivative $\sigma'$, and the derivative of the cost function. With these inclusions you should be able to understand the code in a self-contained way. If something's tripping you up, you may find it helpful to consult [the original description (and complete listing) of the code](http://neuralnetworksanddeeplearning.com/chap1.html#implementing_our_network_to_classify_digits).

```python
class Network(object):
...
   def backprop(self, x, y):
        """Return a tuple "(nabla_b, nabla_w)" representing the
        gradient for the cost function C_x.  "nabla_b" and
        "nabla_w" are layer-by-layer lists of numpy arrays, similar
        to "self.biases" and "self.weights"."""
        nabla_b = [np.zeros(b.shape) for b in self.biases]
        nabla_w = [np.zeros(w.shape) for w in self.weights]
        # feedforward
        activation = x
        activations = [x] # list to store all the activations, layer by layer
        zs = [] # list to store all the z vectors, layer by layer
        for b, w in zip(self.biases, self.weights):
            z = np.dot(w, activation)+b
            zs.append(z)
            activation = sigmoid(z)
            activations.append(activation)
        # backward pass
        delta = self.cost_derivative(activations[-1], y) * \
            sigmoid_prime(zs[-1])
        nabla_b[-1] = delta
        nabla_w[-1] = np.dot(delta, activations[-2].transpose())
        # Note that the variable l in the loop below is used a little
        # differently to the notation in Chapter 2 of the book.  Here,
        # l = 1 means the last layer of neurons, l = 2 is the
        # second-last layer, and so on.  It's a renumbering of the
        # scheme in the book, used here to take advantage of the fact
        # that Python can use negative indices in lists.
        for l in xrange(2, self.num_layers):
            z = zs[-l]
            sp = sigmoid_prime(z)
            delta = np.dot(self.weights[-l+1].transpose(), delta) * sp
            nabla_b[-l] = delta
            nabla_w[-l] = np.dot(delta, activations[-l-1].transpose())
        return (nabla_b, nabla_w)

...

    def cost_derivative(self, output_activations, y):
        """Return the vector of partial derivatives \partial C_x /
        \partial a for the output activations."""
        return (output_activations-y) 

def sigmoid(z):
    """The sigmoid function."""
    return 1.0/(1.0+np.exp(-z))

def sigmoid_prime(z):
    """Derivative of the sigmoid function."""
    return sigmoid(z)*(1-sigmoid(z))
```

[Problem](http://neuralnetworksanddeeplearning.com/chap2.html#problem_269962)

- **Fully matrix-based approach to backpropagation over a mini-batch** Our implementation of stochastic gradient descent loops over training examples <u>in a mini-batch</u>. It's possible to modify the backpropagation algorithm so that it computes the gradients for all training examples in a mini-batch simultaneously. The idea is that instead of beginning with a single input vector, $x$, we can begin with a matrix $X = [x_1 x_2 \ldots x_m]$ whose columns are the vectors in the mini-batch. We forward-propagate by multiplying by the weight matrices, adding a suitable matrix for the bias terms, and applying the sigmoid function everywhere. We backpropagate along similar lines. Explicitly write out pseudocode for this approach to the backpropagation algorithm. Modify `network.py` so that it uses this fully matrix-based approach. The advantage of this approach is that it takes full advantage of modern libraries for linear algebra. As a result it can be quite a bit faster than looping over the mini-batch. (On my laptop, for example, the speedup is about a factor of two when run on MNIST classification problems like those we considered in the last chapter.) In practice, all serious libraries for backpropagation use this fully matrix-based approach or some variant.

### 2.8 [In what sense is backpropagation a fast algorithm?](http://neuralnetworksanddeeplearning.com/chap2.html#in_what_sense_is_backpropagation_a_fast_algorithm)

In what sense is backpropagation a fast algorithm? To answer this question, let's consider another approach to computing the gradient. Imagine it's the early days of neural networks research. Maybe it's the 1950s or 1960s, and you're the first person in the world to think of using gradient descent to learn! But to make the idea work you need a way of computing the gradient of the cost function. You think back to your knowledge of calculus, and decide to see if you can use the chain rule to compute the gradient. But after playing around a bit, the algebra looks complicated, and you get discouraged. So you try to find another approach. You decide to regard the cost as a function of the weights $C = C(w)$ alone (we'll get back to the biases in a moment). You number the weights $w_1, w_2, \ldots$, and want to compute $\partial C / \partial w_j$ for some particular weight $w_j$. An obvious way of doing that is to use the approximation

$$
\begin{eqnarray}  \frac{\partial
    C}{\partial w_{j}} \approx \frac{C(w+\epsilon
    e_j)-C(w)}{\epsilon},
\tag{46}\end{eqnarray}
$$
where $\epsilon > 0$ is a small positive number, and $e_j$ is the unit vector in the $j^{\rm th}$ direction. In other words, we can estimate $\partial C / \partial w_j$ by computing the cost $C$ for two slightly different values of $w_j$, and then applying Equation (46). The same idea will let us compute the partial derivatives $\partial C / \partial b$ with respect to the biases.

This approach looks very promising. It's simple conceptually, and extremely easy to implement, using just a few lines of code. Certainly, it looks much more promising than the idea of using the chain rule to compute the gradient!

Unfortunately, while this approach appears promising, when you implement the code it turns out to be extremely slow. To understand why, imagine we have a million weights in our network. Then for each distinct weight $w_j$ we need to compute $C(w+\epsilon e_j)$ in order to compute $\partial C / \partial w_j$. That means that to compute the gradient we need to compute the cost function a million different times, requiring a million forward passes through the network (per training example). We need to compute $C(w)$ as well, so that's a total of a million and one passes through the network.

What's clever about backpropagation is that it enables us to simultaneously compute *all* the partial derivatives $\partial C / \partial w_j$ using just one forward pass through the network, followed by one backward pass through the network. Roughly speaking, the computational cost of the backward pass is about the same as the forward pass*. And so the total cost of backpropagation is roughly the same as making just two forward passes through the network. Compare that to the million and one forward passes we needed for the approach based on (46)! And so even though backpropagation appears superficially more complex than the approach based on (46), it's actually much, much faster.

>  *This should be plausible, but it requires some analysis to make a careful statement. It's plausible because the dominant computational cost in the forward pass is multiplying by the weight matrices, while in the backward pass it's multiplying by the transposes of the weight matrices. These operations obviously have similar computational cost.

This speedup was first fully appreciated in 1986, and it greatly expanded the range of problems that neural networks could solve. That, in turn, caused a rush of people using neural networks. Of course, backpropagation is not a panacea. Even in the late 1980s people ran up against limits, especially when attempting to use backpropagation to train deep neural networks, i.e., networks with many hidden layers. Later in the book we'll see how modern computers and some clever new ideas now make it possible to use backpropagation to train such deep neural networks.

### 2.9 [Backpropagation: the big picture](http://neuralnetworksanddeeplearning.com/chap2.html#backpropagation_the_big_picture)

As I've explained it, backpropagation presents two mysteries. First, what's the algorithm really doing? We've developed a picture of the error being backpropagated from the output. But can we go any deeper, and build up more intuition about what is going on when we do all these matrix and vector multiplications? The second mystery is how someone could ever have discovered backpropagation in the first place? It's one thing to follow the steps in an algorithm, or even to follow the proof that the algorithm works. But that doesn't mean you understand the problem so well that you could have discovered the algorithm in the first place. Is there a plausible line of reasoning that could have led you to discover the backpropagation algorithm? In this section I'll address both these mysteries.

To improve our intuition about what the algorithm is doing, let's imagine that we've made a small change $\Delta w^l_{jk}$ to some weight in the network, $w^l_{jk}$:

![img](http://neuralnetworksanddeeplearning.com/images/tikz22.png)

That change in weight will cause a change in the output activation from the corresponding neuron:

![img](http://neuralnetworksanddeeplearning.com/images/tikz23.png)

That, in turn, will cause a change in *all* the activations in the next layer:

![img](http://neuralnetworksanddeeplearning.com/images/tikz24.png)

Those changes will in turn cause changes in the next layer, and then the next, and so on all the way through to causing a change in the final layer, and then in the cost function:

![img](http://neuralnetworksanddeeplearning.com/images/tikz25.png)

The change $\Delta C$ in the cost is related to the change $\Delta w^l_{jk}$ in the weight by the equation

$$
\begin{eqnarray} 
  \Delta C \approx \frac{\partial C}{\partial w^l_{jk}} \Delta w^l_{jk}.
\tag{47}\end{eqnarray}
$$
This suggests that a possible approach to computing $\frac{\partial   C}{\partial w^l_{jk}}$ is to carefully track how a small change in $w^l_{jk}$ propagates to cause a small change in $C$. If we can do that, being careful to express everything along the way in terms of easily computable quantities, then we should be able to compute $\partial C / \partial w^l_{jk}$.

Let's try to carry this out. The change $\Delta w^l_{jk}$ causes a small change $\Delta a^{l}_j$ in the activation of the $j^{\rm th}$ neuron in the $l^{\rm th}$ layer. This change is given by

$$
\begin{eqnarray}   \Delta a^l_j \approx \frac{\partial a^l_j}{\partial w^l_{jk}} \Delta w^l_{jk}. \tag{48}\end{eqnarray}
$$

The change in activation $\Delta a^{l}_j$ will cause changes in *all* the activations in the next layer, i.e., the $(l+1)^{\rm th}$ layer. We'll concentrate on the way just a single one of those activations is affected, say $a^{l+1}_q$,

![img](http://neuralnetworksanddeeplearning.com/images/tikz26.png)

In fact, it'll cause the following change:

$$
\begin{eqnarray}
  \Delta a^{l+1}_q \approx \frac{\partial a^{l+1}_q}{\partial a^l_j} \Delta a^l_j.
\tag{49}\end{eqnarray}
$$

Substituting in the expression from Equation (48), we get:

$$
\begin{eqnarray}
  \Delta a^{l+1}_q \approx \frac{\partial a^{l+1}_q}{\partial a^l_j} \frac{\partial a^l_j}{\partial w^l_{jk}} \Delta w^l_{jk}.
\tag{50}\end{eqnarray}
$$
Of course, the change $\Delta a^{l+1}_q$ will, in turn, cause changes in the activations in the next layer. In fact, we can imagine a path all the way through the network from $w^l_{jk}$ to $C$, with each change in activation causing a change in the next activation, and, finally, a change in the cost at the output. If the path goes through activations $a^l_j, a^{l+1}_q, \ldots, a^{L-1}_n, a^L_m$ then the resulting expression is

$$
\begin{eqnarray}
  \Delta C \approx \frac{\partial C}{\partial a^L_m} 
  \frac{\partial a^L_m}{\partial a^{L-1}_n}
  \frac{\partial a^{L-1}_n}{\partial a^{L-2}_p} \ldots
  \frac{\partial a^{l+1}_q}{\partial a^l_j}
  \frac{\partial a^l_j}{\partial w^l_{jk}} \Delta w^l_{jk},
\tag{51}\end{eqnarray}
$$
that is, we've picked up a $\partial a / \partial a$ type term for each additional neuron we've passed through, as well as the $\partial C/\partial a^L_m$ term at the end. This represents the change in $C$ due to changes in the activations along this particular path through the network. Of course, there's many paths by which a change in $w^l_{jk}$ can propagate to affect the cost, and we've been considering just a single path. To compute the total change in $C$ it is plausible that we should sum over all the possible paths between the weight and the final cost, i.e.,
$$
\begin{eqnarray} 
  \Delta C \approx \sum_{mnp\ldots q} \frac{\partial C}{\partial a^L_m} 
  \frac{\partial a^L_m}{\partial a^{L-1}_n}
  \frac{\partial a^{L-1}_n}{\partial a^{L-2}_p} \ldots
  \frac{\partial a^{l+1}_q}{\partial a^l_j} 
  \frac{\partial a^l_j}{\partial w^l_{jk}} \Delta w^l_{jk},
\tag{52}\end{eqnarray}
$$
where we've summed over all possible choices for the intermediate neurons along the path. Comparing with (47) we see that

$$
\begin{eqnarray} 
  \frac{\partial C}{\partial w^l_{jk}} = \sum_{mnp\ldots q} \frac{\partial C}{\partial a^L_m} 
  \frac{\partial a^L_m}{\partial a^{L-1}_n}
  \frac{\partial a^{L-1}_n}{\partial a^{L-2}_p} \ldots
  \frac{\partial a^{l+1}_q}{\partial a^l_j} 
  \frac{\partial a^l_j}{\partial w^l_{jk}}.
\tag{53}\end{eqnarray}
$$
Now, Equation (53) looks complicated. However, it has a nice intuitive interpretation. We're computing the rate of change of $C$ with respect to a weight in the network. What the equation tells us is that every edge between two neurons in the network is associated with a rate factor which is just the partial derivative of one neuron's activation with respect to the other neuron's activation. The edge from the first weight to the first neuron has a rate factor $\partial a^{l}_j / \partial w^l_{jk}$. The rate factor for a path is just the product of the rate factors along the path. And the total rate of change $\partial C / \partial w^l_{jk}$ is just the sum of the rate factors of all paths from the initial weight to the final cost. This procedure is illustrated here, for a single path:

![img](http://neuralnetworksanddeeplearning.com/images/tikz27.png)

What I've been providing up to now is a heuristic argument, a way of thinking about what's going on when you perturb a weight in a network. Let me sketch out a line of thinking you could use to further develop this argument. First, you could derive explicit expressions for all the individual partial derivatives in Equation (53). That's easy to do with a bit of calculus. Having done that, you could then try to figure out how to write all the sums over indices as matrix multiplications. This turns out to be tedious, and requires some persistence, but not extraordinary insight. After doing all this, and then simplifying as much as possible, what you discover is that you end up with exactly the backpropagation algorithm! And so you can think of the backpropagation algorithm as providing a way of computing the sum over the rate factor for all these paths. Or, to put it slightly differently, the backpropagation algorithm is a clever way of keeping track of small perturbations to the weights (and biases) as they propagate through the network, reach the output, and then affect the cost.

Now, I'm not going to work through all this here. It's messy and requires considerable care to work through all the details. If you're up for a challenge, you may enjoy attempting it. And even if not, I hope this line of thinking gives you some insight into what backpropagation is accomplishing.

What about the other mystery - how backpropagation could have been discovered in the first place? In fact, if you follow the approach I just sketched you will discover a proof of backpropagation. Unfortunately, the proof is quite a bit longer and more complicated than the one I described earlier in this chapter. So how was that short (but more mysterious) proof discovered? What you find when you write out all the details of the long proof is that, after the fact, there are several obvious simplifications staring you in the face. You make those simplifications, get a shorter proof, and write that out. And then several more obvious simplifications jump out at you. So you repeat again. The result after a few iterations is the proof we saw earlier*- short, but somewhat obscure, because all the signposts to its construction have been removed! I am, of course, asking you to trust me on this, but there really is no great mystery to the origin of the earlier proof. It's just a lot of hard work simplifying the proof I've sketched in this section.

> *There is one clever step required. In Equation (53) the intermediate variables are activations like $a^{l+1}_q$. The clever idea is to switch to using weighted inputs, like $z^{l+1}_q$, as the intermediate variables. If you don't have this idea, and instead continue using the activations $a^{l+1}_q$, the proof you obtain turns out to be slightly more complex than the proof given earlier in the chapter. 

## 数学

### 如果，$C = \frac{1}{2} \sum_j (y_j-a^L_j)^2$， 那么 $\partial C / \partial a^L_j$ 等于什么？

当损失函数为均方误差 $C = \frac{1}{2} \sum_j (y_j - a_j^L)^2$ 时，对输出层激活值 $a_j^L$ 的偏导数计算如下：

$$
\frac{\partial C}{\partial a_j^L} = a_j^L - y_j
$$

---

**推导过程**： 
1. 损失函数展开为： 
   $$
   C = \frac{1}{2} \sum_k (y_k - a_k^L)^2
   $$
   其中 $k$ 遍历所有输出层神经元。

2. 对特定神经元 $a_j^L$ 求偏导时，只有 $k = j$ 的项对导数有贡献：  
   $$
   \frac{\partial C}{\partial a_j^L} = \frac{\partial}{\partial a_j^L} \left[ \frac{1}{2} (y_j - a_j^L)^2 \right]
   $$

3. 应用链式法则计算：  
   $$
   \frac{\partial C}{\partial a_j^L} = \frac{1}{2} \cdot 2 \cdot (y_j - a_j^L) \cdot (-1) = -(y_j - a_j^L) = a_j^L - y_j
   $$

---

**关键点**： 
- **符号一致性**：结果 $a_j^L - y_j$ 的符号是正向传播误差（预测值减真实值），这与梯度下降中参数更新的方向一致。  
- **仅依赖当前神经元**：导数仅与第 $j$ 个神经元的激活值和真实值相关，与其他神经元无关。 

---

**示例**： 
若 $a_j^L = 0.8$，真实值 $y_j = 1.0$，则： 
$$
\frac{\partial C}{\partial a_j^L} = 0.8 - 1.0 = -0.2
$$
这表示增大 $a_j^L$ 会减少损失 $C$，符合直觉。 

---

**结论**： 
在均方误差下，输出层误差项的完整表达式为： 
$$
\delta_j^L = (a_j^L - y_j) \cdot \sigma'(z_j^L)
$$
这是反向传播中输出层误差计算的核心公式。

### BP1a $\delta^L = \nabla_a C \odot \sigma'(z^L)$ 的解释

该公式是反向传播中计算输出层误差项的核心公式，具体解释如下：

$$
\begin{eqnarray}   \delta^L = \nabla_a C \odot \sigma'(z^L).\tag{BP1a}\end{eqnarray}
$$

1. **符号定义**：
   - **$\delta^L$**：输出层的误差向量，表示每个神经元对总损失的“责任”。  
   - **$\nabla_a C$**：损失函数对输出层激活值 $a^L$ 的梯度向量，即 $\frac{\partial C}{\partial a^L}$。  
   - **$\sigma'(z^L)$**：激活函数在输出层加权输入 $z^L$ 处的导数向量。  
   - **$\odot$**：逐元素相乘（哈达玛积）。

2. **物理意义**：
   - **$\nabla_a C$**：量化损失函数如何随输出层激活值的变化而变化。  
     - 例如，对于均方误差损失 $C = \frac{1}{2} \sum_j (y_j - a_j^L)^2$，有 $\frac{\partial C}{\partial a_j^L} = a_j^L - y_j$，即 $\nabla_a C = a^L - y$。  
   - **$\sigma'(z^L)$**：捕捉激活函数对加权输入的敏感度。若激活函数饱和（如 Sigmoid 两端），$\sigma'(z^L)$ 趋近于零，误差会被抑制。  
   - **逐元素相乘**：将损失梯度与激活函数导数结合，得到每个神经元的最终误差贡献。

3. **示例**：
   假设输出层有 2 个神经元，真实值 $y = [1, 0]$，预测值 $a^L = [0.9, 0.2]$，激活函数为 Sigmoid，则：
   - $\nabla_a C = [0.9 - 1, 0.2 - 0] = [-0.1, 0.2]$  
   - $\sigma'(z^L) = \sigma(z^L)(1 - \sigma(z^L)) = [0.9 \cdot 0.1, 0.2 \cdot 0.8] = [0.09, 0.16]$  
   - $\delta^L = [-0.1 \cdot 0.09, 0.2 \cdot 0.16] = [-0.009, 0.032]$

---

#### 为什么需要这个公式？
- **误差反向传播的起点**：输出层误差 $\delta^L$ 是反向传播的初始信号，后续通过链式法则逐层计算隐藏层误差（如 $\delta^{L-1} = (W^L)^\top \delta^L \odot \sigma'(z^{L-1})$）。  
- **分离损失函数与激活函数的影响**：$\nabla_a C$ 反映损失函数的设计（如均方误差、交叉熵），而 $\sigma'(z^L)$ 反映激活函数的非线性特性，两者共同决定误差的传播强度。

---

#### 关键点总结：
1. **通用性**：公式适用于任意可微损失函数和激活函数。  
2. **逐神经元计算**：每个神经元的误差仅依赖其自身的激活值和真实值，与其他神经元无关。  
3. **反向传播的基石**：输出层误差 $\delta^L$ 是计算权重和偏置梯度的起点，最终驱动参数更新。  

---

#### 公式的直观理解：
- **误差放大与抑制**：若激活函数导数 $\sigma'(z_j^L)$ 较大（如神经元处于激活状态），则误差会被放大；若导数较小（如神经元饱和），误差会被抑制。  
- **梯度方向**：$\nabla_a C$ 的符号指示了激活值应调整的方向（增大或减小以降低损失）。

### BP2 $\delta^l = ((w^{l+1})^T \delta^{l+1}) \odot \sigma'(z^l)$ 的解释